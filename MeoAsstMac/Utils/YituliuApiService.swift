//
//  YituliuApiService.swift
//  MAA
//
//  Created by zhangweijian on 22/9/2026.
//

import Foundation

/// 一图流第三方 OpenAPI，用于读取干员练度数据。
///
/// 鉴权方式为请求头 Authorization 直接携带 token（不加 Bearer 前缀），
/// 业务结果看响应体 code 而非 HTTP 状态码。
enum YituliuApiService {
    private static let operatorInfoURL = URL(string: "https://backend.yituliu.cn/open-api/operator/info")!

    private static let codeSuccess = 200
    private static let codeInsufficientPermissions = 20010
    private static let codeInvalidCredentials = 20027

    enum TokenValidationResult: Equatable {
        /// token 有效且具备读取权限
        case valid
        /// token 有效但只有写入权限，无法读取
        case writeOnly
        /// token 无效或已失效
        case invalid
        /// 网络请求失败
        case networkError

        var description: String {
            switch self {
            case .valid:
                return ""
            case .writeOnly:
                return String(localized: "Token 不具备读取权限，请使用只读或读写权限的 Token")
            case .invalid:
                return String(localized: "Token 无效或已失效，请重新生成")
            case .networkError:
                return String(localized: "网络错误，请稍后重试")
            }
        }
    }

    /// 干员练度数据响应，业务结果看 `code` 而非 HTTP 状态码。
    private struct OperatorInfoResponse: Decodable {
        let code: Int
        let msg: String?
        let data: [OperatorInfo]?
    }

    /// 干员练度数据（一图流 V2 格式），只有练度没有名称与星级。
    struct OperatorInfo: Decodable {
        /// 干员 ID（如 char_002_amiya）
        let id: String
        /// 等级
        let level: Int?
        /// 精英化阶段（0~2）
        let evolvePhase: Int?
        /// 主技能等级（1~7）
        let mainSkillLevel: Int?
        /// 潜能等级（1~6）
        let potentialRank: Int?
        /// 技能专精
        let skills: [Skill]?
        /// 模组
        let equips: [Equip]?
    }

    /// 技能专精数据
    struct Skill: Decodable {
        let id: String
        /// 专精等级（0~3）
        let level: Int
    }

    /// 模组数据
    struct Equip: Decodable {
        let id: String
        /// 模组分支（X/Y 等）
        let type: String?
        /// 模组等级
        let level: Int
    }

    /// 拉取干员练度数据，成功时返回干员列表，失败时返回验证结果供提示。
    static func operatorInfo(token: String) async -> (result: TokenValidationResult, data: [OperatorInfo]?) {
        guard let body = await request(token: token) else {
            return (.networkError, nil)
        }

        let result = validationResult(of: body.code)
        return (result, result == .valid ? body.data : nil)
    }

    /// 请求干员练度数据。
    ///
    /// 请求本身失败（网络错误、响应不是预期格式）时返回 nil。
    private static func request(token: String) async -> OperatorInfoResponse? {
        var request = URLRequest(url: operatorInfoURL)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(OperatorInfoResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private static func validationResult(of code: Int) -> TokenValidationResult {
        switch code {
        case codeSuccess:
            return .valid
        case codeInsufficientPermissions:
            return .writeOnly
        case codeInvalidCredentials:
            return .invalid
        default:
            return .invalid
        }
    }
}
