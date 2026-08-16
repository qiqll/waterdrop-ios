import Foundation

struct Item: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let location: String
    var category: String
    var description: String
    var createTime: String
    var updateTime: String
    var imageUrl: String?
    var status: Int
    var remark: String?
    var operatorUser: String

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
        operatorUser: String = ""
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
    }
}
