import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Stack } from "@prism/components/Stack";
import { Text } from "@prism/components/Text";
import { theme } from "@prism/theme";
import type { ActionNotificationModel } from "../contracts";

export function ActionNotification({
	notification,
	onDismiss,
	onConfirm,
}: {
	readonly notification?: ActionNotificationModel;
	readonly onDismiss?: () => void;
	readonly onConfirm?: (action: string) => void;
}): React.ReactElement {
	if (notification === undefined) return <></>;
	return (
		<frame
			AnchorPoint={new Vector2(1, 0)}
			Position={new UDim2(1, -24, 0, 24)}
			Size={UDim2.fromOffset(400, 142)}
			BackgroundColor3={Color3.fromRGB(24, 24, 26)}
			BorderSizePixel={0}
			ZIndex={100}
		>
			<uicorner CornerRadius={new UDim(0, 10)} />
			<uistroke Color={Color3.fromRGB(76, 76, 82)} Transparency={0.25} Thickness={1} />
			<uipadding PaddingTop={new UDim(0, 14)} PaddingBottom={new UDim(0, 14)} PaddingLeft={new UDim(0, 16)} PaddingRight={new UDim(0, 16)} />
			<Stack width="100%" gap="sm">
				<Text text={notification.title} size="md" weight={700} color={theme.text.primary} width="100%" />
				<Text
					text={notification.text}
					size="sm"
					color={theme.text.secondary}
					width="100%"
					slotProps={{ root: { TextWrapped: true, TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Stack width="100%" direction="horizontal" justify="spaceBetween" gap="sm">
					<Button label="Not Now" variant="outline" width="48%" onPress={() => onDismiss?.()} />
					<Button
						label={notification.confirmLabel ?? "Enable"}
						variant="filled"
						color={notification.tone ?? "warning"}
						width="48%"
						onPress={() => onConfirm?.(notification.action)}
					/>
				</Stack>
			</Stack>
		</frame>
	);
}
