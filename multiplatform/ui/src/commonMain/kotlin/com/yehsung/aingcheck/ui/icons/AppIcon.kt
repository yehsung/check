// 원본: google/material-design-icons @ 49d4db35df873165d6bd6ba09b063c7dafbac2f4 — Material Symbols Rounded(wght 400 · GRAD 0 · opsz 24), Apache-2.0
// 원본 대응: Sources/**/*.swift @ 862be0f 의 SF Symbols 이름(SfSymbols.kt) — 출처·sha256 표는 ui/snapshots/icons/material-symbols-source.tsv
//
// 앱 아이콘 집합(D§13-3 → G §8-1 #13: Fluent 대신 Material Symbols). SF Symbols 는 애플 플랫폼 밖에서 쓰지 않는다.
// 그림은 composeResources/drawable/ms_<이름>[_fill].xml(벡터) — 채움 0/1 은 따로 그린 두 장이다(축 보간이 아니다).
package com.yehsung.aingcheck.ui.icons

import com.yehsung.aingcheck.ui.resources.Res
import com.yehsung.aingcheck.ui.resources.ms_account_box
import com.yehsung.aingcheck.ui.resources.ms_account_circle
import com.yehsung.aingcheck.ui.resources.ms_account_circle_fill
import com.yehsung.aingcheck.ui.resources.ms_add
import com.yehsung.aingcheck.ui.resources.ms_add_circle_fill
import com.yehsung.aingcheck.ui.resources.ms_alarm_on
import com.yehsung.aingcheck.ui.resources.ms_apartment_fill
import com.yehsung.aingcheck.ui.resources.ms_apps_fill
import com.yehsung.aingcheck.ui.resources.ms_arrow_circle_down
import com.yehsung.aingcheck.ui.resources.ms_arrow_forward
import com.yehsung.aingcheck.ui.resources.ms_arrow_left_fill
import com.yehsung.aingcheck.ui.resources.ms_arrow_right_fill
import com.yehsung.aingcheck.ui.resources.ms_arrow_upward
import com.yehsung.aingcheck.ui.resources.ms_auto_awesome
import com.yehsung.aingcheck.ui.resources.ms_av_timer_fill
import com.yehsung.aingcheck.ui.resources.ms_badge
import com.yehsung.aingcheck.ui.resources.ms_badge_fill
import com.yehsung.aingcheck.ui.resources.ms_bar_chart
import com.yehsung.aingcheck.ui.resources.ms_block
import com.yehsung.aingcheck.ui.resources.ms_bolt_fill
import com.yehsung.aingcheck.ui.resources.ms_brush_fill
import com.yehsung.aingcheck.ui.resources.ms_calendar_clock
import com.yehsung.aingcheck.ui.resources.ms_campaign
import com.yehsung.aingcheck.ui.resources.ms_cancel_fill
import com.yehsung.aingcheck.ui.resources.ms_celebration_fill
import com.yehsung.aingcheck.ui.resources.ms_chat_fill
import com.yehsung.aingcheck.ui.resources.ms_chat_bubble
import com.yehsung.aingcheck.ui.resources.ms_chat_bubble_fill
import com.yehsung.aingcheck.ui.resources.ms_check
import com.yehsung.aingcheck.ui.resources.ms_check_circle_fill
import com.yehsung.aingcheck.ui.resources.ms_checklist
import com.yehsung.aingcheck.ui.resources.ms_chess
import com.yehsung.aingcheck.ui.resources.ms_chevron_left
import com.yehsung.aingcheck.ui.resources.ms_chevron_right
import com.yehsung.aingcheck.ui.resources.ms_circle
import com.yehsung.aingcheck.ui.resources.ms_circle_fill
import com.yehsung.aingcheck.ui.resources.ms_close
import com.yehsung.aingcheck.ui.resources.ms_cloud_off_fill
import com.yehsung.aingcheck.ui.resources.ms_contact_support
import com.yehsung.aingcheck.ui.resources.ms_content_copy
import com.yehsung.aingcheck.ui.resources.ms_contrast
import com.yehsung.aingcheck.ui.resources.ms_crown_fill
import com.yehsung.aingcheck.ui.resources.ms_cruelty_free_fill
import com.yehsung.aingcheck.ui.resources.ms_dangerous_fill
import com.yehsung.aingcheck.ui.resources.ms_dark_mode
import com.yehsung.aingcheck.ui.resources.ms_dark_mode_fill
import com.yehsung.aingcheck.ui.resources.ms_delete
import com.yehsung.aingcheck.ui.resources.ms_desktop_windows
import com.yehsung.aingcheck.ui.resources.ms_diamond_fill
import com.yehsung.aingcheck.ui.resources.ms_directions_run_fill
import com.yehsung.aingcheck.ui.resources.ms_drafts_fill
import com.yehsung.aingcheck.ui.resources.ms_eco_fill
import com.yehsung.aingcheck.ui.resources.ms_edit
import com.yehsung.aingcheck.ui.resources.ms_edit_square
import com.yehsung.aingcheck.ui.resources.ms_equal
import com.yehsung.aingcheck.ui.resources.ms_error_fill
import com.yehsung.aingcheck.ui.resources.ms_expand_less
import com.yehsung.aingcheck.ui.resources.ms_expand_more
import com.yehsung.aingcheck.ui.resources.ms_extension
import com.yehsung.aingcheck.ui.resources.ms_extension_fill
import com.yehsung.aingcheck.ui.resources.ms_feedback
import com.yehsung.aingcheck.ui.resources.ms_feedback_fill
import com.yehsung.aingcheck.ui.resources.ms_filter_list
import com.yehsung.aingcheck.ui.resources.ms_filter_none
import com.yehsung.aingcheck.ui.resources.ms_flag
import com.yehsung.aingcheck.ui.resources.ms_flag_fill
import com.yehsung.aingcheck.ui.resources.ms_flutter_dash_fill
import com.yehsung.aingcheck.ui.resources.ms_forum
import com.yehsung.aingcheck.ui.resources.ms_forum_fill
import com.yehsung.aingcheck.ui.resources.ms_grid_on
import com.yehsung.aingcheck.ui.resources.ms_grid_view_fill
import com.yehsung.aingcheck.ui.resources.ms_group
import com.yehsung.aingcheck.ui.resources.ms_group_fill
import com.yehsung.aingcheck.ui.resources.ms_groups
import com.yehsung.aingcheck.ui.resources.ms_groups_fill
import com.yehsung.aingcheck.ui.resources.ms_help
import com.yehsung.aingcheck.ui.resources.ms_hourglass_empty
import com.yehsung.aingcheck.ui.resources.ms_how_to_reg
import com.yehsung.aingcheck.ui.resources.ms_inbox
import com.yehsung.aingcheck.ui.resources.ms_info
import com.yehsung.aingcheck.ui.resources.ms_info_fill
import com.yehsung.aingcheck.ui.resources.ms_install_desktop_fill
import com.yehsung.aingcheck.ui.resources.ms_ios_share
import com.yehsung.aingcheck.ui.resources.ms_key
import com.yehsung.aingcheck.ui.resources.ms_key_fill
import com.yehsung.aingcheck.ui.resources.ms_keyboard
import com.yehsung.aingcheck.ui.resources.ms_light_mode
import com.yehsung.aingcheck.ui.resources.ms_local_fire_department_fill
import com.yehsung.aingcheck.ui.resources.ms_lock
import com.yehsung.aingcheck.ui.resources.ms_lock_fill
import com.yehsung.aingcheck.ui.resources.ms_lock_reset
import com.yehsung.aingcheck.ui.resources.ms_logout
import com.yehsung.aingcheck.ui.resources.ms_mail
import com.yehsung.aingcheck.ui.resources.ms_mail_fill
import com.yehsung.aingcheck.ui.resources.ms_mark_email_unread_fill
import com.yehsung.aingcheck.ui.resources.ms_memory
import com.yehsung.aingcheck.ui.resources.ms_menu_book
import com.yehsung.aingcheck.ui.resources.ms_menu_book_fill
import com.yehsung.aingcheck.ui.resources.ms_mood
import com.yehsung.aingcheck.ui.resources.ms_more_horiz
import com.yehsung.aingcheck.ui.resources.ms_north_east
import com.yehsung.aingcheck.ui.resources.ms_notifications
import com.yehsung.aingcheck.ui.resources.ms_notifications_fill
import com.yehsung.aingcheck.ui.resources.ms_notifications_off
import com.yehsung.aingcheck.ui.resources.ms_notifications_off_fill
import com.yehsung.aingcheck.ui.resources.ms_notifications_unread
import com.yehsung.aingcheck.ui.resources.ms_notifications_unread_fill
import com.yehsung.aingcheck.ui.resources.ms_pan_tool_alt_fill
import com.yehsung.aingcheck.ui.resources.ms_pause_fill
import com.yehsung.aingcheck.ui.resources.ms_pause_circle
import com.yehsung.aingcheck.ui.resources.ms_pause_circle_fill
import com.yehsung.aingcheck.ui.resources.ms_percent
import com.yehsung.aingcheck.ui.resources.ms_person
import com.yehsung.aingcheck.ui.resources.ms_person_fill
import com.yehsung.aingcheck.ui.resources.ms_person_add
import com.yehsung.aingcheck.ui.resources.ms_person_off_fill
import com.yehsung.aingcheck.ui.resources.ms_photo_camera_fill
import com.yehsung.aingcheck.ui.resources.ms_photo_library
import com.yehsung.aingcheck.ui.resources.ms_play_arrow_fill
import com.yehsung.aingcheck.ui.resources.ms_power_settings_new
import com.yehsung.aingcheck.ui.resources.ms_question_mark
import com.yehsung.aingcheck.ui.resources.ms_redeem_fill
import com.yehsung.aingcheck.ui.resources.ms_refresh
import com.yehsung.aingcheck.ui.resources.ms_remove
import com.yehsung.aingcheck.ui.resources.ms_reply_fill
import com.yehsung.aingcheck.ui.resources.ms_rotate_left
import com.yehsung.aingcheck.ui.resources.ms_running_with_errors
import com.yehsung.aingcheck.ui.resources.ms_schedule
import com.yehsung.aingcheck.ui.resources.ms_schedule_fill
import com.yehsung.aingcheck.ui.resources.ms_send_fill
import com.yehsung.aingcheck.ui.resources.ms_settings
import com.yehsung.aingcheck.ui.resources.ms_settings_fill
import com.yehsung.aingcheck.ui.resources.ms_shield
import com.yehsung.aingcheck.ui.resources.ms_shopping_bag
import com.yehsung.aingcheck.ui.resources.ms_shopping_bag_fill
import com.yehsung.aingcheck.ui.resources.ms_show_chart
import com.yehsung.aingcheck.ui.resources.ms_signal_wifi_bad
import com.yehsung.aingcheck.ui.resources.ms_smartphone
import com.yehsung.aingcheck.ui.resources.ms_speed
import com.yehsung.aingcheck.ui.resources.ms_splitscreen_landscape_fill
import com.yehsung.aingcheck.ui.resources.ms_sports_esports_fill
import com.yehsung.aingcheck.ui.resources.ms_sports_score
import com.yehsung.aingcheck.ui.resources.ms_star_fill
import com.yehsung.aingcheck.ui.resources.ms_stop_fill
import com.yehsung.aingcheck.ui.resources.ms_sync
import com.yehsung.aingcheck.ui.resources.ms_tag
import com.yehsung.aingcheck.ui.resources.ms_target
import com.yehsung.aingcheck.ui.resources.ms_timer
import com.yehsung.aingcheck.ui.resources.ms_top_panel_open
import com.yehsung.aingcheck.ui.resources.ms_touch_app_fill
import com.yehsung.aingcheck.ui.resources.ms_trophy_fill
import com.yehsung.aingcheck.ui.resources.ms_undo
import com.yehsung.aingcheck.ui.resources.ms_verified_fill
import com.yehsung.aingcheck.ui.resources.ms_verified_user_fill
import com.yehsung.aingcheck.ui.resources.ms_vertical_align_bottom
import com.yehsung.aingcheck.ui.resources.ms_visibility
import com.yehsung.aingcheck.ui.resources.ms_warning
import com.yehsung.aingcheck.ui.resources.ms_warning_fill
import com.yehsung.aingcheck.ui.resources.ms_wb_twilight_fill
import org.jetbrains.compose.resources.DrawableResource

enum class AppIcon(val materialName: String, val filled: Boolean) {
    AccountBox("account_box", false),
    AccountCircle("account_circle", false),
    AccountCircleFill("account_circle", true),
    Add("add", false),
    AddCircleFill("add_circle", true),
    AlarmOn("alarm_on", false),
    ApartmentFill("apartment", true),
    AppsFill("apps", true),
    ArrowCircleDown("arrow_circle_down", false),
    ArrowForward("arrow_forward", false),
    ArrowLeftFill("arrow_left", true),
    ArrowRightFill("arrow_right", true),
    ArrowUpward("arrow_upward", false),
    AutoAwesome("auto_awesome", false),
    AvTimerFill("av_timer", true),
    Badge("badge", false),
    BadgeFill("badge", true),
    BarChart("bar_chart", false),
    Block("block", false),
    BoltFill("bolt", true),
    BrushFill("brush", true),
    CalendarClock("calendar_clock", false),
    Campaign("campaign", false),
    CancelFill("cancel", true),
    CelebrationFill("celebration", true),
    ChatFill("chat", true),
    ChatBubble("chat_bubble", false),
    ChatBubbleFill("chat_bubble", true),
    Check("check", false),
    CheckCircleFill("check_circle", true),
    Checklist("checklist", false),
    Chess("chess", false),
    ChevronLeft("chevron_left", false),
    ChevronRight("chevron_right", false),
    Circle("circle", false),
    CircleFill("circle", true),
    Close("close", false),
    CloudOffFill("cloud_off", true),
    ContactSupport("contact_support", false),
    ContentCopy("content_copy", false),
    Contrast("contrast", false),
    CrownFill("crown", true),
    CrueltyFreeFill("cruelty_free", true),
    DangerousFill("dangerous", true),
    DarkMode("dark_mode", false),
    DarkModeFill("dark_mode", true),
    Delete("delete", false),
    DesktopWindows("desktop_windows", false),
    DiamondFill("diamond", true),
    DirectionsRunFill("directions_run", true),
    DraftsFill("drafts", true),
    EcoFill("eco", true),
    Edit("edit", false),
    EditSquare("edit_square", false),
    Equal("equal", false),
    ErrorFill("error", true),
    ExpandLess("expand_less", false),
    ExpandMore("expand_more", false),
    Extension("extension", false),
    ExtensionFill("extension", true),
    Feedback("feedback", false),
    FeedbackFill("feedback", true),
    FilterList("filter_list", false),
    FilterNone("filter_none", false),
    Flag("flag", false),
    FlagFill("flag", true),
    FlutterDashFill("flutter_dash", true),
    Forum("forum", false),
    ForumFill("forum", true),
    GridOn("grid_on", false),
    GridViewFill("grid_view", true),
    Group("group", false),
    GroupFill("group", true),
    Groups("groups", false),
    GroupsFill("groups", true),
    Help("help", false),
    HourglassEmpty("hourglass_empty", false),
    HowToReg("how_to_reg", false),
    Inbox("inbox", false),
    Info("info", false),
    InfoFill("info", true),
    InstallDesktopFill("install_desktop", true),
    IosShare("ios_share", false),
    Key("key", false),
    KeyFill("key", true),
    Keyboard("keyboard", false),
    LightMode("light_mode", false),
    LocalFireDepartmentFill("local_fire_department", true),
    Lock("lock", false),
    LockFill("lock", true),
    LockReset("lock_reset", false),
    Logout("logout", false),
    Mail("mail", false),
    MailFill("mail", true),
    MarkEmailUnreadFill("mark_email_unread", true),
    Memory("memory", false),
    MenuBook("menu_book", false),
    MenuBookFill("menu_book", true),
    Mood("mood", false),
    MoreHoriz("more_horiz", false),
    NorthEast("north_east", false),
    Notifications("notifications", false),
    NotificationsFill("notifications", true),
    NotificationsOff("notifications_off", false),
    NotificationsOffFill("notifications_off", true),
    NotificationsUnread("notifications_unread", false),
    NotificationsUnreadFill("notifications_unread", true),
    PanToolAltFill("pan_tool_alt", true),
    PauseFill("pause", true),
    PauseCircle("pause_circle", false),
    PauseCircleFill("pause_circle", true),
    Percent("percent", false),
    Person("person", false),
    PersonFill("person", true),
    PersonAdd("person_add", false),
    PersonOffFill("person_off", true),
    PhotoCameraFill("photo_camera", true),
    PhotoLibrary("photo_library", false),
    PlayArrowFill("play_arrow", true),
    PowerSettingsNew("power_settings_new", false),
    QuestionMark("question_mark", false),
    RedeemFill("redeem", true),
    Refresh("refresh", false),
    Remove("remove", false),
    ReplyFill("reply", true),
    RotateLeft("rotate_left", false),
    RunningWithErrors("running_with_errors", false),
    Schedule("schedule", false),
    ScheduleFill("schedule", true),
    SendFill("send", true),
    Settings("settings", false),
    SettingsFill("settings", true),
    Shield("shield", false),
    ShoppingBag("shopping_bag", false),
    ShoppingBagFill("shopping_bag", true),
    ShowChart("show_chart", false),
    SignalWifiBad("signal_wifi_bad", false),
    Smartphone("smartphone", false),
    Speed("speed", false),
    SplitscreenLandscapeFill("splitscreen_landscape", true),
    SportsEsportsFill("sports_esports", true),
    SportsScore("sports_score", false),
    StarFill("star", true),
    StopFill("stop", true),
    Sync("sync", false),
    Tag("tag", false),
    Target("target", false),
    Timer("timer", false),
    TopPanelOpen("top_panel_open", false),
    TouchAppFill("touch_app", true),
    TrophyFill("trophy", true),
    Undo("undo", false),
    VerifiedFill("verified", true),
    VerifiedUserFill("verified_user", true),
    VerticalAlignBottom("vertical_align_bottom", false),
    Visibility("visibility", false),
    Warning("warning", false),
    WarningFill("warning", true),
    WbTwilightFill("wb_twilight", true),
    ;

    /** composeResources/drawable 안 파일 이름(확장자 뺀 것). [drawable] 이 이 이름의 리소스를 가리키는지 시험이 잰다(생성된 Res 의 이름표와 대조). */
    val resourceName: String get() = "ms_" + materialName + if (filled) "_fill" else ""

    val drawable: DrawableResource
        get() = when (this) {
            AccountBox -> Res.drawable.ms_account_box
            AccountCircle -> Res.drawable.ms_account_circle
            AccountCircleFill -> Res.drawable.ms_account_circle_fill
            Add -> Res.drawable.ms_add
            AddCircleFill -> Res.drawable.ms_add_circle_fill
            AlarmOn -> Res.drawable.ms_alarm_on
            ApartmentFill -> Res.drawable.ms_apartment_fill
            AppsFill -> Res.drawable.ms_apps_fill
            ArrowCircleDown -> Res.drawable.ms_arrow_circle_down
            ArrowForward -> Res.drawable.ms_arrow_forward
            ArrowLeftFill -> Res.drawable.ms_arrow_left_fill
            ArrowRightFill -> Res.drawable.ms_arrow_right_fill
            ArrowUpward -> Res.drawable.ms_arrow_upward
            AutoAwesome -> Res.drawable.ms_auto_awesome
            AvTimerFill -> Res.drawable.ms_av_timer_fill
            Badge -> Res.drawable.ms_badge
            BadgeFill -> Res.drawable.ms_badge_fill
            BarChart -> Res.drawable.ms_bar_chart
            Block -> Res.drawable.ms_block
            BoltFill -> Res.drawable.ms_bolt_fill
            BrushFill -> Res.drawable.ms_brush_fill
            CalendarClock -> Res.drawable.ms_calendar_clock
            Campaign -> Res.drawable.ms_campaign
            CancelFill -> Res.drawable.ms_cancel_fill
            CelebrationFill -> Res.drawable.ms_celebration_fill
            ChatFill -> Res.drawable.ms_chat_fill
            ChatBubble -> Res.drawable.ms_chat_bubble
            ChatBubbleFill -> Res.drawable.ms_chat_bubble_fill
            Check -> Res.drawable.ms_check
            CheckCircleFill -> Res.drawable.ms_check_circle_fill
            Checklist -> Res.drawable.ms_checklist
            Chess -> Res.drawable.ms_chess
            ChevronLeft -> Res.drawable.ms_chevron_left
            ChevronRight -> Res.drawable.ms_chevron_right
            Circle -> Res.drawable.ms_circle
            CircleFill -> Res.drawable.ms_circle_fill
            Close -> Res.drawable.ms_close
            CloudOffFill -> Res.drawable.ms_cloud_off_fill
            ContactSupport -> Res.drawable.ms_contact_support
            ContentCopy -> Res.drawable.ms_content_copy
            Contrast -> Res.drawable.ms_contrast
            CrownFill -> Res.drawable.ms_crown_fill
            CrueltyFreeFill -> Res.drawable.ms_cruelty_free_fill
            DangerousFill -> Res.drawable.ms_dangerous_fill
            DarkMode -> Res.drawable.ms_dark_mode
            DarkModeFill -> Res.drawable.ms_dark_mode_fill
            Delete -> Res.drawable.ms_delete
            DesktopWindows -> Res.drawable.ms_desktop_windows
            DiamondFill -> Res.drawable.ms_diamond_fill
            DirectionsRunFill -> Res.drawable.ms_directions_run_fill
            DraftsFill -> Res.drawable.ms_drafts_fill
            EcoFill -> Res.drawable.ms_eco_fill
            Edit -> Res.drawable.ms_edit
            EditSquare -> Res.drawable.ms_edit_square
            Equal -> Res.drawable.ms_equal
            ErrorFill -> Res.drawable.ms_error_fill
            ExpandLess -> Res.drawable.ms_expand_less
            ExpandMore -> Res.drawable.ms_expand_more
            Extension -> Res.drawable.ms_extension
            ExtensionFill -> Res.drawable.ms_extension_fill
            Feedback -> Res.drawable.ms_feedback
            FeedbackFill -> Res.drawable.ms_feedback_fill
            FilterList -> Res.drawable.ms_filter_list
            FilterNone -> Res.drawable.ms_filter_none
            Flag -> Res.drawable.ms_flag
            FlagFill -> Res.drawable.ms_flag_fill
            FlutterDashFill -> Res.drawable.ms_flutter_dash_fill
            Forum -> Res.drawable.ms_forum
            ForumFill -> Res.drawable.ms_forum_fill
            GridOn -> Res.drawable.ms_grid_on
            GridViewFill -> Res.drawable.ms_grid_view_fill
            Group -> Res.drawable.ms_group
            GroupFill -> Res.drawable.ms_group_fill
            Groups -> Res.drawable.ms_groups
            GroupsFill -> Res.drawable.ms_groups_fill
            Help -> Res.drawable.ms_help
            HourglassEmpty -> Res.drawable.ms_hourglass_empty
            HowToReg -> Res.drawable.ms_how_to_reg
            Inbox -> Res.drawable.ms_inbox
            Info -> Res.drawable.ms_info
            InfoFill -> Res.drawable.ms_info_fill
            InstallDesktopFill -> Res.drawable.ms_install_desktop_fill
            IosShare -> Res.drawable.ms_ios_share
            Key -> Res.drawable.ms_key
            KeyFill -> Res.drawable.ms_key_fill
            Keyboard -> Res.drawable.ms_keyboard
            LightMode -> Res.drawable.ms_light_mode
            LocalFireDepartmentFill -> Res.drawable.ms_local_fire_department_fill
            Lock -> Res.drawable.ms_lock
            LockFill -> Res.drawable.ms_lock_fill
            LockReset -> Res.drawable.ms_lock_reset
            Logout -> Res.drawable.ms_logout
            Mail -> Res.drawable.ms_mail
            MailFill -> Res.drawable.ms_mail_fill
            MarkEmailUnreadFill -> Res.drawable.ms_mark_email_unread_fill
            Memory -> Res.drawable.ms_memory
            MenuBook -> Res.drawable.ms_menu_book
            MenuBookFill -> Res.drawable.ms_menu_book_fill
            Mood -> Res.drawable.ms_mood
            MoreHoriz -> Res.drawable.ms_more_horiz
            NorthEast -> Res.drawable.ms_north_east
            Notifications -> Res.drawable.ms_notifications
            NotificationsFill -> Res.drawable.ms_notifications_fill
            NotificationsOff -> Res.drawable.ms_notifications_off
            NotificationsOffFill -> Res.drawable.ms_notifications_off_fill
            NotificationsUnread -> Res.drawable.ms_notifications_unread
            NotificationsUnreadFill -> Res.drawable.ms_notifications_unread_fill
            PanToolAltFill -> Res.drawable.ms_pan_tool_alt_fill
            PauseFill -> Res.drawable.ms_pause_fill
            PauseCircle -> Res.drawable.ms_pause_circle
            PauseCircleFill -> Res.drawable.ms_pause_circle_fill
            Percent -> Res.drawable.ms_percent
            Person -> Res.drawable.ms_person
            PersonFill -> Res.drawable.ms_person_fill
            PersonAdd -> Res.drawable.ms_person_add
            PersonOffFill -> Res.drawable.ms_person_off_fill
            PhotoCameraFill -> Res.drawable.ms_photo_camera_fill
            PhotoLibrary -> Res.drawable.ms_photo_library
            PlayArrowFill -> Res.drawable.ms_play_arrow_fill
            PowerSettingsNew -> Res.drawable.ms_power_settings_new
            QuestionMark -> Res.drawable.ms_question_mark
            RedeemFill -> Res.drawable.ms_redeem_fill
            Refresh -> Res.drawable.ms_refresh
            Remove -> Res.drawable.ms_remove
            ReplyFill -> Res.drawable.ms_reply_fill
            RotateLeft -> Res.drawable.ms_rotate_left
            RunningWithErrors -> Res.drawable.ms_running_with_errors
            Schedule -> Res.drawable.ms_schedule
            ScheduleFill -> Res.drawable.ms_schedule_fill
            SendFill -> Res.drawable.ms_send_fill
            Settings -> Res.drawable.ms_settings
            SettingsFill -> Res.drawable.ms_settings_fill
            Shield -> Res.drawable.ms_shield
            ShoppingBag -> Res.drawable.ms_shopping_bag
            ShoppingBagFill -> Res.drawable.ms_shopping_bag_fill
            ShowChart -> Res.drawable.ms_show_chart
            SignalWifiBad -> Res.drawable.ms_signal_wifi_bad
            Smartphone -> Res.drawable.ms_smartphone
            Speed -> Res.drawable.ms_speed
            SplitscreenLandscapeFill -> Res.drawable.ms_splitscreen_landscape_fill
            SportsEsportsFill -> Res.drawable.ms_sports_esports_fill
            SportsScore -> Res.drawable.ms_sports_score
            StarFill -> Res.drawable.ms_star_fill
            StopFill -> Res.drawable.ms_stop_fill
            Sync -> Res.drawable.ms_sync
            Tag -> Res.drawable.ms_tag
            Target -> Res.drawable.ms_target
            Timer -> Res.drawable.ms_timer
            TopPanelOpen -> Res.drawable.ms_top_panel_open
            TouchAppFill -> Res.drawable.ms_touch_app_fill
            TrophyFill -> Res.drawable.ms_trophy_fill
            Undo -> Res.drawable.ms_undo
            VerifiedFill -> Res.drawable.ms_verified_fill
            VerifiedUserFill -> Res.drawable.ms_verified_user_fill
            VerticalAlignBottom -> Res.drawable.ms_vertical_align_bottom
            Visibility -> Res.drawable.ms_visibility
            Warning -> Res.drawable.ms_warning
            WarningFill -> Res.drawable.ms_warning_fill
            WbTwilightFill -> Res.drawable.ms_wb_twilight_fill
        }
}
