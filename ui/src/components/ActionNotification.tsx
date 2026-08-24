import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Stack } from "@prism/components/Stack";
import { Text } from "@prism/components/Text";
import { theme } from "@prism/theme";
import type { ActionNotificationModel } from "../contracts";

const TweenService = game.GetService("TweenService");

function placement(position: ActionNotificationModel["position"]): {
	readonly anchor: Vector2;
	readonly start: UDim2;
	readonly target: UDim2;
} {
	const margin = 24;
	switch (position) {
		case "top-left":
			return { anchor: new Vector2(0, 0), start: new UDim2(0, margin - 18, 0, margin), target: new UDim2(0, margin, 0, margin) };
		case "top-center":
			return { anchor: new Vector2(0.5, 0), start: new UDim2(0.5, 0, 0, margin - 18), target: new UDim2(0.5, 0, 0, margin) };
		case "bottom-left":
			return { anchor: new Vector2(0, 1), start: new UDim2(0, margin - 18, 1, -margin), target: new UDim2(0, margin, 1, -margin) };
		case "bottom-center":
			return { anchor: new Vector2(0.5, 1), start: new UDim2(0.5, 0, 1, -margin + 18), target: new UDim2(0.5, 0, 1, -margin) };
		case "bottom-right":
			return { anchor: new Vector2(1, 1), start: new UDim2(1, -margin + 18, 1, -margin), target: new UDim2(1, -margin, 1, -margin) };
		default:
			return { anchor: new Vector2(1, 0), start: new UDim2(1, -margin + 18, 0, margin), target: new UDim2(1, -margin, 0, margin) };
	}
}

export function ActionNotification({
	notification,
	onDismiss,
	onConfirm,
}: {
	readonly notification?: ActionNotificationModel;
	readonly onDismiss?: () => void;
	readonly onConfirm?: (action: string) => void;
}): React.ReactElement {
	const groupRef = React.useRef<CanvasGroup>();
	const position = placement(notification?.position);
	React.useEffect(() => {
		const group = groupRef.current;
		if (group === undefined || notification === undefined) return;
		group.GroupTransparency = 1;
		group.Position = position.start;
		const tween = TweenService.Create(
			group,
			new TweenInfo(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ GroupTransparency: 0, Position: position.target },
		);
		tween.Play();
		return () => tween.Cancel();
	}, [notification]);

	if (notification === undefined) return <></>;
	const close = (callback?: () => void) => {
		const group = groupRef.current;
		if (group === undefined) {
			callback?.();
			return;
		}
		const tween = TweenService.Create(
			group,
			new TweenInfo(0.17, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ GroupTransparency: 1, Position: position.start },
		);
		tween.Completed.Once(() => callback?.());
		tween.Play();
	};
	return (
		<canvasgroup
			ref={groupRef}
			AnchorPoint={position.anchor}
			Position={position.target}
			Size={UDim2.fromOffset(496, 140)}
			BackgroundColor3={Color3.fromRGB(20, 20, 22)}
			BorderSizePixel={0}
			ZIndex={100}
		>
			<uicorner CornerRadius={new UDim(0, 12)} />
			<uistroke Color={Color3.fromRGB(72, 72, 78)} Transparency={0.45} Thickness={1} />
			<uipadding PaddingTop={new UDim(0, 17)} PaddingBottom={new UDim(0, 14)} PaddingLeft={new UDim(0, 18)} PaddingRight={new UDim(0, 18)} />
			<textbutton
				Position={new UDim2(1, -26, 0, -8)}
				Size={UDim2.fromOffset(26, 26)}
				BackgroundTransparency={1}
				BorderSizePixel={0}
				Text="×"
				TextColor3={Color3.fromRGB(150, 150, 158)}
				TextSize={24}
				Font={Enum.Font.GothamMedium}
				Event={{ Activated: () => close(onDismiss) }}
			/>
			<Stack width="100%" gap="sm">
				<Text
					text={notification.title}
					size="md"
					weight={800}
					color={theme.text.primary}
					width="100%"
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Text
					text={notification.text}
					size="sm"
					color={theme.text.secondary}
					width="100%"
					slotProps={{ root: { TextWrapped: true, TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Stack width="100%" direction="horizontal" justify="end" gap="xs">
					<Button label="Not Now" variant="subtle" color="primary" width={104} onPress={() => close(onDismiss)} />
					<Button
						label={notification.confirmLabel ?? "Enable"}
						variant="filled"
						color="primary"
						width={104}
						onPress={() => close(() => onConfirm?.(notification.action))}
					/>
				</Stack>
			</Stack>
		</canvasgroup>
	);
}
