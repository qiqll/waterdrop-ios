import Foundation

struct Item: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var location: String
    var category: String
    var description: String
    var createTime: String
    var updateTime: String
    var imageUrl: String?
    var status: Int
    var remark: String?
    var operatorUser: String

    // MARK: - F-011：补齐服务端 Item 实体已有、此前被 toItem() 静默丢弃的字段
    // 这些字段仅「写入时回传 + 读取时展示」，本地不做业务加工。

    /// 详细位置（如「客厅电视柜第二层」）
    var locationDetail: String?
    /// 标签（服务端为逗号分隔字符串）
    var tags: String?
    /// 价值/金额
    var value: Double?
    /// 品牌
    var brand: String?
    /// 型号
    var model: String?
    /// 序列号 / SN
    var serialNumber: String?
    /// 购买日期（yyyy-MM-dd）
    var purchaseDate: String?
    /// 保修信息
    var warranty: String?
    /// 数量
    var quantity: Int?
    /// 单位（个/台/件…）
    var unit: String?
    /// 所属分组 ID
    var groupId: String?

    init(
        id: String = "",
        name: String,
        location: String,
        category: String = "",
        description: String = "",
        createTime: String = "",
        updateTime: String = "",
        imageUrl: String? = nil,
        status: Int = 1,
        remark: String? = nil,
        operatorUser: String = "",
        locationDetail: String? = nil,
        tags: String? = nil,
        value: Double? = nil,
        brand: String? = nil,
        model: String? = nil,
        serialNumber: String? = nil,
        purchaseDate: String? = nil,
        warranty: String? = nil,
        quantity: Int? = nil,
        unit: String? = nil,
        groupId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.category = category
        self.description = description
        self.createTime = createTime
        self.updateTime = updateTime
        self.imageUrl = imageUrl
        self.status = status
        self.remark = remark
        self.operatorUser = operatorUser
        self.locationDetail = locationDetail
        self.tags = tags
        self.value = value
        self.brand = brand
        self.model = model
        self.serialNumber = serialNumber
        self.purchaseDate = purchaseDate
        self.warranty = warranty
        self.quantity = quantity
        self.unit = unit
        self.groupId = groupId
    }
}
