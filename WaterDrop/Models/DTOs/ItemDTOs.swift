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
            operatorUser: createBy ?? ""
        )
    }
}

// MARK: - Item Create/Update Request

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
