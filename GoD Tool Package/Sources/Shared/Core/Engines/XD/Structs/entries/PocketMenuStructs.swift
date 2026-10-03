import Structs
import GoDFoundation

/// `pocket_menu.rel`'s shop dialogue tables, named from the shop code that
/// reads them (`couponProc`, `couponExchangeMain`, `shopProc`, `shopBuyMain`,
/// `getMsgID` / `getCouponMsgID`). Colosseum's readers mirror XD's
/// instruction for instruction and its tables have the same layout.
public extension XDStructDefaults {

    static let shopCouponDialogStruct = StructMap(
        name: "ShopCouponDialog",
        wordSize: 4,
        alignmentStyle: .none,
        properties: shopDialogHeader + [
            .uint32(name: "greeting_msg"),
            .uint32(name: "anything_else_msg"),
            .uint32(name: "farewell_msg"),
            .uint32(name: "choose_prize_msg"),
            .uint32(name: "not_enough_coupons_msg"),
            .uint32(name: "confirm_msg"),
            .uint32(name: "received_msg"),
            .uint32(name: "exchange_again_msg"),
            .uint32(name: "cannot_afford_msg"),
            .uint32(name: "no_room_msg"),
            .uint32(name: "prize_list_msg"),
            .uint32(name: "explanation_msg"),
            .uint32(name: "quantity_msg"),
            .uint32(name: "quit_msg"),
            .uint32(name: "link_off_msg", description: "Unread in XD (no GBA link); Colosseum: \"Please turn off the GBA\""),
            .uint32(name: "transfer_msg"),
            .uint32(name: "retry_msg", description: "Unread in XD"),
            .uint32(name: "cancel_msg", description: "Unread in XD"),
        ],
        description: "A coupon counter's messages (0x4C bytes; message slot = MENU_COUPON_MSG_CODE)"
    )

    static let shopGreetingDialogStruct = StructMap(
        name: "ShopGreetingDialog",
        wordSize: 4,
        alignmentStyle: .none,
        properties: shopDialogHeader + [
            .uint32(name: "greeting_msg"),
            .uint32(name: "anything_else_msg"),
            .uint32(name: "farewell_msg"),
            .uint32(name: "confirm_purchase_msg"),
            .uint32(name: "thank_you_msg"),
            .uint32(name: "not_enough_money_msg"),
            .uint32(name: "no_room_msg"),
            .uint32(name: "premier_ball_bonus_msg"),
            .uint32(name: "needs_cologne_case_msg"),
            .uint32(name: "sell_offer_msg", description: "Unread in XD, which has no selling"),
            .uint32(name: "unknown_sell_msg", description: "Unread in XD; an empty string on every row of both games"),
            .uint32(name: "cannot_buy_msg", description: "Unread in XD"),
            .uint32(name: "quantity_buy_msg"),
            .uint32(name: "quantity_sell_msg", description: "Unread in XD"),
        ],
        description: "A shop clerk's messages (0x3C bytes; message slot = MENU_SHOP_MSG_CODE)"
    )

    static var shopDialogHeader: [StructMap.Property] {
        [
            .uint8(name: "message_se_type", description: "Window sound, looked up in common.rel's message sounds"),
            .padding(length: 3),
        ]
    }

    /// The mart list (XD `shopData`, Colosseum `MartStartIndexes`): one row
    /// per mart, which `getGoodsList` and the shop menu index by mart id.
    static let shopStruct = StructMap(
        name: "Shop",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "dialog_index", description: "Row of the greeting table (shops) or the coupon-counter table (coupon kinds)"),
            .abstraction(name: "shop_kind", typeName: "ShopKind"),
            .uint16(name: "first_item_index", description: "Where this mart's run starts in the goods table; must be the start of a run"),
        ],
        description: "A mart (4 bytes)"
    )

    /// The mart goods (XD `shopGoods`, Colosseum `MartItems`): one flat list,
    /// a zero-terminated run per mart. Runs may be shared by several marts.
    static let shopGoodsEntryStruct = StructMap(
        name: "ShopGoodsEntry",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "item_data_id", description: "An item *data id*, mapped to an Items row through common.rel's ValidItems; identical below 500, above it the row is lower (XD id − 150, Colosseum id − 151), which is why this isn't typed as Items. 0 ends the mart's run"),
        ],
        description: "One item in a mart's run (2 bytes)"
    )
}
