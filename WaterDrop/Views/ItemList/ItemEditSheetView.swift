import SwiftUI
import PhotosUI

/// 编辑物品对话框：可修改位置、备注、状态、图片（名称/类别保持不变）。
/// 对齐 Android `ItemListActivity.showEditDialog` —— 位置/备注输入 + 状态下拉「正常/已借出/已丢失/已损坏」→ int 1..4。
struct ItemEditSheetView: View {
    let item: Item
    /// 保存成功后回调，用于外层刷新列表。
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var location: String
    @State private var remark: String
    @State private var status: Int

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    // F-001: 图片选择
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var pickedMimeType: String = "image/jpeg"

    private let statusLabels = ["正常", "已借出", "已丢失", "已损坏"]

    init(item: Item, onSaved: @escaping () async -> Void) {
        self.item = item
        self.onSaved = onSaved
        _location = State(initialValue: item.location)
        _remark = State(initialValue: item.remark ?? "")
        _status = State(initialValue: item.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 图片预览 + 选择
                    HStack(spacing: 12) {
                        Group {
                            if let data = pickedImageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                            } else if let imageUrl = item.imageUrl,
                                      let resolved = ServerConfig.resolveImageUrl(imageUrl) {
                                AuthenticatedRemoteImage(urlString: resolved)
                            } else {
                                Image(systemName: "photo")
                                    .font(.wd(.headlineLarge))
                                    .foregroundStyle(ThemeManager.shared.palette.neutral400)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .background(ThemeManager.shared.palette.neutral100)

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label(pickedImageData == nil ? "选择图片" : "更换图片", systemImage: "photo.badge.plus")
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("图片")
                }

                Section {
                    TextField("存放位置", text: $location)
                } header: {
                    Text("位置")
                }

                Section {
                    TextField("备注（可选）", text: $remark)
                } header: {
                    Text("备注")
                }

                Section {
                    Picker("状态", selection: $status) {
                        ForEach(1...4, id: \.self) { value in
                            Text(statusLabels[value - 1]).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("状态")
                }
            }
            .navigationTitle("编辑：\(item.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("提示", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            // 监听选中图片，取回数据
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        pickedImageData = data
                        pickedMimeType = dataHeuristicMimeType(data) ?? "image/jpeg"
                    }
                }
            }
        }
    }

    /// 根据图片数据头推断 MIME 类型（供上传 Content-Type 使用）。
    private func dataHeuristicMimeType(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if data[0] == 0x89, data[1] == 0x50 {
            return "image/png"
        }
        // JPEG: FF D8 FF
        if data[0] == 0xFF, data[1] == 0xD8 {
            return "image/jpeg"
        }
        // GIF: "GIF8"
        if data[0] == 0x47, data[1] == 0x49, data[2] == 0x46 {
            return "image/gif"
        }
        // WEBP: "RIFF"...."WEBP"
        if data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data.count >= 12, data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50 {
            return "image/webp"
        }
        return nil
    }

    private func save() {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            errorMessage = "位置不能为空"
            showError = true
            return
        }

        isSaving = true
        Task {
            let trimmedRemark = remark.trimmingCharacters(in: .whitespacesAndNewlines)

            // D-4 契约：remark 传 "" 表示用户主动清空；不能传 nil（nil 在服务端是「本次不修改」，
            // 清空会静默失效）。本 sheet 只编辑位置/备注/状态，其余服务端字段
            // （brand/model/quantity…）由 Request(from:) 原样带上，避免被服务端
            // updateById 的 NOT_NULL 策略漏掉而永远无法修改。
            var edited = item
            edited.location = trimmedLocation
            edited.remark = trimmedRemark
            edited.status = status
            var request = ItemCreateRequest(from: edited)

            // 若选择了新图片，先上传得到 fileUrl，再随物品信息一起更新。
            if let data = pickedImageData {
                do {
                    if let uploadedUrl = try await FileAPIService.uploadImage(data: data, mimeType: pickedMimeType) {
                        var withImage = edited
                        withImage.imageUrl = uploadedUrl
                        request = ItemCreateRequest(from: withImage)
                    } else {
                        isSaving = false
                        errorMessage = "图片上传失败，未保存更改"
                        showError = true
                        return
                    }
                } catch {
                    isSaving = false
                    errorMessage = "图片上传失败，未保存更改"
                    showError = true
                    return
                }
            }

            let success = await ItemRepository.shared.update(id: item.id, request)
            isSaving = false
            if success {
                await onSaved()
                dismiss()
            } else {
                errorMessage = "更新失败，请检查网络后重试"
                showError = true
            }
        }
    }
}
