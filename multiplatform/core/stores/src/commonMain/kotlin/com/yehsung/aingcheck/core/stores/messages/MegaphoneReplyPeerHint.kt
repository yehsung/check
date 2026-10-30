// 원본: Sources/CheckMobileKit/Messages/MegaphoneBannerPhoneRules.swift `MegaphoneReplyPeerHint` @ a6791165(57810a8e)
package com.yehsung.aingcheck.core.stores.messages

/** [답장]이 대화 화면에 넘기는 이름·아바타 — 확성기 줄이 메시지함에서 빠져 대화가 비어 있어도 머리가 빈 칸이 아니게. */
data class MegaphoneReplyPeerHint(val name: String?, val avatarURL: String?)
