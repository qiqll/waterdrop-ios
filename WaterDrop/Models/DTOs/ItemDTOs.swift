import Foundation

// MARK: - Item DTO (server response)

struct ItemDto: Codable {
    let id: String
    let userId: String?
    let groupId: String?
    let name: String
    let description: String?
    let category: String?
    let location: String?
    let locationDetail: String?
    let imageUrl: String?
    let tags: String?
    let value: Double?
    let brand: String?
    let model: String?
    let serialNumber: String?
    let purchaseDate: String?
    let warranty: String?
    let quantity: Int?
    let unit: String?
    let status: Int?
    let remark: String?
    let createTime: String?
    let updateTime: String?
    let createBy: String?
    let updateBy: String?

    func toItem() -> Item {
        Item(
            id: id,
            name: name,
            location: location ?? "",
            category: category ?? "",
            description: description ?? "",
            createTime: createTime ?? "",
            updateTime: updateTime ?? "",
            imageUrl: imageUrl,
            status: status ?? 1,
            remark: remark,
            operatorUser: createBy ?? "",
            // F-011：以下 11 个字段此前被静默丢弃，导致只写不读
            locationDetail: locationDetail,
            tags: tags,
            value: value,
            brand: brand,
            model: model,
            serialNumber: serialNumber,
            purchaseDate: purchaseDate,
            warranty: warranty,
            quantity: quantity,
            unit: unit,
            groupId: groupId
        )
    }
}

// MARK: - Item Create/Update Request

extension ItemCreateRequest {
    /// F-011：Item -> 写请求。
    ///
    /// 更新/创建一律回传本地已知的全部业务字段，而非只传 7 个。原因（见 D-4 契约）：
    /// 服务端 updateById 走 MyBatis-Plus 默认 NOT_NULL 策略，请求里为 nil 的字段会被跳过更新。
    /// 若这里不全量回传，那些字段在客户端就永远无法被修改（不是「保持不变」，而是「不可达」）。
    ///
    /// 注意：id / userId / createTime / createBy / updateTime / updateBy 由服务端维护，此处不传。
    init(from item: Item) {
        self.init(
            name: item.name,
            location: item.location,
            description: item.description,
            category: item.category,
            locationDetail: item.locationDetail,
            imageUrl: item.imageUrl,
            tags: item.tags,
            value: item.value,
            brand: item.brand,
            model: item.model,
            serialNumber: item.serialNumber,
            purchaseDate: item.purchaseDate,
            warranty: item.warranty,
            quantity: item.quantity,
            unit: item.unit,
            remark: item.remark,
            groupId: item.groupId,
            status: item.status
        )
    }
}

struct ItemCreateRequest: Codable {
    let name: String
    let location: String
    let description: String?
    let category: String?
    let locationDetail: String?
    let imageUrl: String?
    let tags: String?
    let value: Double?
    let brand: String?
    let model: String?
    let serialNumber: String?
    let purchaseDate: String?
    let warranty: String?
    let quantity: Int?
    let unit: String?
    let remark: String?
    let groupId: String?
    let status: Int?

    init(
        name: String,
        location: String,
        description: String? = nil,
        category: String? = nil,
        locationDetail: String? = nil,
        imageUrl: String? = nil,
        tags: String? = nil,
        value: Double? = nil,
        brand: String? = nil,
        model: String? = nil,
        serialNumber: String? = nil,
        purchaseDate: String? = nil,
        warranty: String? = nil,
        quantity: Int? = nil,
        unit: String? = nil,
        remark: String? = nil,
        groupId: String? = nil,
        status: Int? = nil
    ) {
        self.name = name
        self.location = location
        self.description = description
        self.category = category
        self.locationDetail = locationDetail
        self.imageUrl = imageUrl
        self.tags = tags
        self.value = value
        self.brand = brand
        self.model = model
        self.serialNumber = serialNumber
        self.purchaseDate = purchaseDate
        self.warranty = warranty
        self.quantity = quantity
        self.unit = unit
        self.remark = remark
        self.groupId = groupId
        self.status = status
    }
}

// MARK: - Item Search Request

struct ItemSearchRequest: Codable {
    let keyword: String?
    let category: String?
    let location: String?
    let groupId: String?
    let status: Int?
    let page: Int
    let size: Int

    init(
        keyword: String? = nil,
        category: String? = nil,
        location: String? = nil,
        groupId: String? = nil,
        status: Int? = nil,
        page: Int = 1,
        size: Int = 20
    ) {
        self.keyword = keyword
        self.category = category
        self.location = location
        self.groupId = groupId
        self.status = status
        self.page = page
        self.size = size
    }
}
