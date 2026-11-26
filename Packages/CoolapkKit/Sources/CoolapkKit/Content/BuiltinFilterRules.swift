import Foundation

public enum BuiltinFilterRules: Sendable {
    private static let fixedDate = Date(timeIntervalSince1970: 1_793_059_200) // 2026-10-26 UTC

    public static let defaultRuleSet = FilterRuleSet(
        revision: 1,
        publishedAt: fixedDate,
        rules: [
            FilterRule(
                id: "topic.partner-showcase",
                reason: "伴侣展示话题",
                kind: .topic,
                values: ["110066", "我在酷安晒女友"],
                reviewedAt: fixedDate,
                sources: ["https://www.coolapk.com/t/我在酷安晒女友"]
            ),
            FilterRule(
                id: "author.partner-showcase.1007278",
                reason: "持续发布伴侣展示内容",
                kind: .author,
                values: ["1007278"],
                reviewedAt: fixedDate,
                sources: ["https://www.coolapk.com/u/1007278"]
            ),
            FilterRule(
                id: "author.model-series.10202630",
                reason: "持续发布模特／Cos摄影系列",
                kind: .author,
                values: ["10202630"],
                reviewedAt: fixedDate,
                sources: ["https://www.coolapk.com/u/10202630"]
            ),
            FilterRule(
                id: "text.explicit-solicitation",
                reason: "明确的性邀约",
                kind: .text,
                scopes: [.feed, .comment],
                groups: [["想约炮", "求约炮", "来约炮", "一起约炮", "找人约炮", "约炮吗", "约炮么"]],
                exceptions: ["反对", "拒绝", "不要", "抵制", "警惕", "骚扰", "举报", "困扰"]
            ),
            FilterRule(
                id: "text.explicit-objectification",
                reason: "明确的性意淫表达",
                kind: .text,
                scopes: [.feed, .comment],
                groups: [["想操她", "想艹她", "想操这个妹", "想艹这个妹", "想操这女的", "想艹这女的"]],
                maxDistance: 24
            ),
            FilterRule(
                id: "text.strict-suggestive-solicitation",
                reason: "性暗示索取内容",
                kind: .text,
                level: .strict,
                scopes: [.feed, .comment],
                groups: [["女菩萨"], ["发福利"]],
                maxDistance: 32
            ),
            FilterRule(
                id: "text.strict-comment-spouse-bait",
                reason: "评论中的性化起哄",
                kind: .text,
                level: .strict,
                scopes: [.comment],
                groups: [["叫我老公", "叫声老公", "现在得叫老公"]]
            )
        ]
    )
}
