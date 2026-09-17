#if os(iOS)
import CheckCore
import PhotosUI
import SwiftUI

/// 프로필 편집: 사진(PhotosPicker → 256px JPEG → 업로드) · 별명(12자 · 7일 쿨타임).
struct MeProfileView: View {
    let store: MeStore
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var nameFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 112

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AingCard {
                    VStack(spacing: 12) {
                        ZStack {
                            AvatarView(name: store.displayName ?? "나", url: store.avatarURL, size: avatarSize)
                            if store.isUploadingAvatar {
                                Circle().fill(Color.black.opacity(0.35))
                                    .frame(width: avatarSize, height: avatarSize)
                                ProgressView().tint(.white)
                            }
                        }
                        let pickerTitle = store.isUploadingAvatar ? MeText.avatarUploading : MeText.avatarChange
                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Label(pickerTitle, systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(AingPrimaryButtonStyle(fillsWidth: false))
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
                        .foregroundStyle(MobileTheme.primaryText)
                    Text(MeText.displayNameHelp)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField(MeText.displayNameLabel, text: $store.displayNameDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(save)
                            .disabled(store.isDisplayNameLocked || store.isUpdatingDisplayName)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MobileTheme.cardElevated))
                            .accessibilityLabel(Text(MeText.displayNameLabel))
                        Text("\(store.displayNameDraftLength)/\(MeStore.displayNameMaxLength)")
                            .font(MobileTheme.number(.footnote))
                            .monospacedDigit()
                            .foregroundStyle(store.displayNameDraftLength > MeStore.displayNameMaxLength ? MobileTheme.danger : MobileTheme.secondaryText)
                            .fixedSize()
                            .accessibilityLabel(Text("\(store.displayNameDraftLength)자, 최대 \(MeStore.displayNameMaxLength)자"))
                    }
                    if let notice = store.displayNameNotice {
                        InlineNotice(text: notice, kind: store.isDisplayNameNoticeError ? .error : .info)
                    }
                    Button(action: save) {
                        if store.isUpdatingDisplayName {
                            ProgressView().tint(MobileTheme.onAccent)
                        } else {
                            Text(MeText.displayNameSave)
                        }
                    }
                    .buttonStyle(AingPrimaryButtonStyle())
                    .disabled(!store.canSaveDisplayName)
                }
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

    private func save() {
        guard store.canSaveDisplayName else { return }
        nameFocused = false
        Task { await store.saveDisplayName() }
    }
}
#endif
