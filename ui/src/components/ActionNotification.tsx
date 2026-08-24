import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Stack } from "@prism/components/Stack";
import { Text } from "@prism/components/Text";
import { theme } from "@prism/theme";
import type { ActionNotificationModel } from "../contracts";

const TweenService = game.GetService("TweenService");
const TONE_COLORS = {
	success: Color3.fromRGB(82, 205, 138),
	warning: Color3.fromRGB(245, 184, 75),
	error: Color3.fromRGB(255, 132, 74),
};

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
	const tone = notification.tone ?? "warning";
	const toneColor = TONE_COLORS[tone];
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
			Size={UDim2.fromOffset(400, 150)}
			BackgroundColor3={Color3.fromRGB(24, 24, 27)}
			BorderSizePixel={0}
			ZIndex={100}
		>
			<uicorner CornerRadius={new UDim(0, 10)} />
			<uistroke Color={Color3.fromRGB(76, 76, 82)} Transparency={0.35} Thickness={1} />
			<frame Size={new UDim2(1, 0, 0, 3)} BackgroundColor3={toneColor} BorderSizePixel={0}>
				<uicorner CornerRadius={new UDim(0, 10)} />
			</frame>
			<uipadding PaddingTop={new UDim(0, 15)} PaddingBottom={new UDim(0, 14)} PaddingLeft={new UDim(0, 16)} PaddingRight={new UDim(0, 16)} />
			<Stack width="100%" gap="sm">
				<Stack width="100%" direction="horizontal" align="center" gap="sm">
					<frame Size={UDim2.fromOffset(28, 28)} BackgroundColor3={toneColor} BackgroundTransparency={0.82} BorderSizePixel={0}>
						<uicorner CornerRadius={new UDim(0, 7)} />
						<Text text="!" size="md" weight={800} color={toneColor} width="100%" height="100%" />
					</frame>
					<Text text={notification.title} size="md" weight={800} color={theme.text.primary} width={320} />
				</Stack>
				<Text
					text={notification.text}
					size="sm"
					color={theme.text.secondary}
					width="100%"
					slotProps={{ root: { TextWrapped: true, TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Stack width="100%" direction="horizontal" justify="spaceBetween" gap="sm">
					<Button label="Not Now" variant="outline" width="48%" onPress={() => close(onDismiss)} />
					<Button
						label={notification.confirmLabel ?? "Enable"}
						variant="filled"
						color={tone}
						width="48%"
						onPress={() => close(() => onConfirm?.(notification.action))}
					/>
				</Stack>
			</Stack>
		</canvasgroup>
	);
}
