#if os(iOS)
import CheckCore
import PhotosUI
import SwiftUI

/// 프로필 편집: 사진(PhotosPicker → 256px JPEG → 업로드) · 별명(12자 · 7일 쿨타임).
/// 채운 버튼은 [저장] 하나 — 드물게 쓰는 [사진 바꾸기]는 틴트(w14 비평 28). 사진·별명은 다른 사람에게 보이는 모습이고, 내 화면에는
/// 착용 캐릭터가 선다는 것을 아래 카드가 밝힌다(무엇이 '나'로 쓰이는지).
struct MeProfileView: View {
    let store: MeStore
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var nameFocused: Bool
    /// 기본 글자 크기의 지름 — 큰 글자에서는 `AvatarView` 공용 규칙이 키운다.
    private let avatarSize: CGFloat = 96

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                AingCard {
                    VStack(spacing: MobileTheme.rowSpacing) {
                        AvatarView(name: store.displayName ?? "나", url: store.avatarURL, size: avatarSize)
                            .overlay {
                                // 덮개는 아바타 자신의 틀을 따른다(글자 배율로 커진 지름과 같게).
                                if store.isUploadingAvatar {
                                    Circle().fill(Color.black.opacity(0.35))
                                    ProgressView().tint(.white)
                                }
                            }
                        Text(MeText.avatarRoleNote)
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        let pickerTitle = store.isUploadingAvatar ? MeText.avatarUploading : MeText.avatarChange
                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Label(pickerTitle, systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(AingButtonStyle(.tinted, size: .md))
                        .disabled(store.isUploadingAvatar)
                        if let notice = store.avatarNotice {
                            InlineNotice(text: notice, kind: store.isAvatarNoticeError ? .error : .info)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                AingCard {
                    Text(MeText.displayNameLabel)
                        .font(.headline)
                        .foregroundStyle(MobileTheme.label)
                    Text(MeText.displayNameHelp)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: MobileTheme.space2) {
                        TextField(MeText.displayNameLabel, text: $store.displayNameDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(save)
                            .disabled(store.isDisplayNameLocked || store.isUpdatingDisplayName)
                            .accessibilityLabel(Text(MeText.displayNameLabel))
                        // 글자 수는 입력칸 **안** 오른쪽(칸 밖에 두면 칸이 짧아졌다 — w11 캡처 35).
                        Text("\(store.displayNameDraftLength)/\(MeStore.displayNameMaxLength)")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(store.displayNameDraftLength > MeStore.displayNameMaxLength ? MobileTheme.danger : MobileTheme.label3Text)
                            .fixedSize()
                            .accessibilityLabel(Text("\(store.displayNameDraftLength)자, 최대 \(MeStore.displayNameMaxLength)자"))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.fill))
                    if let notice = store.displayNameNotice {
                        InlineNotice(text: notice, kind: store.isDisplayNameNoticeError ? .error : .info)
                    }
                    AingButton(MeText.displayNameSave, kind: .filled, size: .lg, fillsWidth: true, isBusy: store.isUpdatingDisplayName, action: save)
                        .disabled(!store.canSaveDisplayName)
                }

                characterRoleCard
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MeText.profileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.profileDidAppear() }
        .onDisappear { store.profileDidDisappear() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    await store.uploadAvatar(imageData: Data())
                    return
                }
                await store.uploadAvatar(imageData: data)
            }
        }
    }

    /// 내 화면에 서는 것은 착용 캐릭터 — 초상 + 한 줄 + [캐릭터 바꾸기] 행.
    private var characterRoleCard: some View {
        Button {
            store.context.router.push(MeDestination.characters, on: .me)
        } label: {
            HStack(spacing: MobileTheme.space3) {
                CharacterPortrait(id: store.equippedCharacterID, mood: .plain, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MeText.characterRoleTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(MeText.characterRoleNote)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(MeText.changeCharacter)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MobileTheme.accent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.label3)
                    .accessibilityHidden(true)
            }
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func save() {
        guard store.canSaveDisplayName else { return }
        nameFocused = false
        Task { await store.saveDisplayName() }
    }
}
#endif
