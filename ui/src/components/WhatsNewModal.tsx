import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Modal } from "@prism/components/Modal";
import { ScrollArea } from "@prism/components/ScrollArea";
import { Stack } from "@prism/components/Stack";
import { Text } from "@prism/components/Text";
import { theme } from "@prism/theme";
import type { WhatsNewModel } from "../contracts";

export function WhatsNewModal({
	notice,
	onAction,
}: {
	readonly notice?: WhatsNewModel;
	readonly onAction?: (name: string) => void;
}): React.ReactElement {
	return (
		<Modal
			opened={notice?.visible === true}
			onClose={() => onAction?.("whatsNewDismiss")}
			title="What's New"
			size="lg"
			closeOnBackdropClick
			withCloseButton
		>
			<Stack width="100%" gap="md">
				<Text
					text={notice?.releases?.[0]?.displayVersion ?? notice?.current ?? ""}
					size="sm"
					weight={700}
					color={theme.text.disabled}
					width="100%"
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<ScrollArea width="100%" height={320} direction="vertical" scrollbarSize={3}>
					<Stack width="100%" gap="lg">
						{(notice?.entries ?? []).map((release) => (
							<Stack key={release.version} width="100%" gap="sm">
								<Text text={release.title} size="lg" weight={800} color={theme.text.primary} width="100%" />
								<Text
									text={release.channel === "beta" ? `${release.date} · Beta` : release.date}
									size="xs"
									weight={600}
									color={theme.text.disabled}
									width="100%"
								/>
								{(release.sections ?? []).map((section) => {
									const tone =
										section.id === "added"
											? theme.success.main
											: section.id === "changed"
												? theme.primary.main
												: section.id === "fixed"
													? theme.info.main
													: section.id === "removed"
														? theme.error.main
														: theme.warning.main;
									return (
										<Stack key={section.id} width="100%" gap="xs">
											<Text text={section.label.upper()} size="xs" weight={800} color={tone} width="100%" />
											{(section.groups ?? [{ tab: "", items: section.items.map((name) => ({ name })) }]).map((group) => (
												<Stack key={group.tab || group.items[0]?.name || section.id} width="100%" gap="xs">
													{group.tab !== "" && <Text text={group.tab} size="sm" weight={800} color={theme.text.primary} />}
													{group.items.map((feature) => (
														<Text
															key={feature.name}
															text={"note" in feature && feature.note ? `${feature.name} - ${feature.note}` : feature.name}
															size="sm"
															weight={600}
															color={theme.text.secondary}
															width="100%"
															slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left, TextWrapped: true } }}
														/>
													))}
												</Stack>
											))}
										</Stack>
									);
								})}
							</Stack>
						))}
					</Stack>
				</ScrollArea>
				<Stack width="100%" direction="horizontal" gap="sm">
					<Button label="Don't show again" variant="outline" onPress={() => onAction?.("whatsNewDontShowAgain")} />
					<Button label="View all" variant="outline" onPress={() => onAction?.("whatsNewViewAll")} />
					<Button label="Got it" variant="filled" onPress={() => onAction?.("whatsNewAcknowledge")} />
				</Stack>
			</Stack>
		</Modal>
	);
}
