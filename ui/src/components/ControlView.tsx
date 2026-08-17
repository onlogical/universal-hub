import React from "@rbxts/react";
import { Box, Button, KeybindInput, SegmentedControl, Slider, Stack, Switch, Text } from "@prism";
import { theme } from "@prism/theme";
import type { MenuControl, UniversalHubMenuModel } from "../contracts";
import { HUB_THEME } from "../theme";
import { EditableKeycap } from "./Keycap";

function valueText(value: number, unit?: string): string {
	return `${math.round(value)}${unit === undefined ? "" : ` ${unit}`}`;
}

function intentColor(intent: "primary" | "success" | "warning" | "error" | "info") {
	switch (intent) {
		case "success":
			return theme.success.main;
		case "warning":
			return theme.warning.main;
		case "error":
			return theme.error.main;
		case "info":
			return theme.info.main;
		default:
			return theme.primary.main;
	}
}

export function ControlView({
	control,
	model,
	hideLabel = false,
	compact = false,
}: {
	readonly control: MenuControl;
	readonly model: UniversalHubMenuModel;
	readonly hideLabel?: boolean;
	readonly compact?: boolean;
}): React.ReactElement {
	const disabled = control.disabled === true || control.status === "unavailable" || control.status === "standby";
	if (control.kind === "segmented") {
		const prominent = control.emphasis === "prominent";
		return (
			<Stack
				width="100%"
				direction={prominent ? "vertical" : "horizontal"}
				align="center"
				justify="spaceBetween"
				gap={prominent ? "sm" : "md"}
			>
				{!hideLabel && (
					<Text
						text={control.label}
						size="md"
						weight={600}
						color={theme.text.primary}
						width={prominent ? "100%" : 120}
						slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
					/>
				)}
				<SegmentedControl
					options={control.options}
					value={control.value}
					onChange={(value) => model.onValueChange(control.id, value, true)}
					variant="subtle"
					color="primary"
					size="md"
					styleOverrides={{
						frame: (_styles, context) => ({
							backgroundColor: context.theme.colors.background.default,
							strokeColor: context.theme.colors.border.subtle,
							strokeTransparency: 0.35,
						}),
						segment: (_styles, context) => ({
							backgroundColor: context.theme.colors.background.surface,
							backgroundTransparency: 1,
							strokeColor: context.theme.colors.border.subtle,
							strokeTransparency: 1,
							textColor:
								context.state === "selected" ? context.theme.colors.primary.main : context.theme.colors.text.secondary,
							textTransparency: context.state === "disabled" ? 0.45 : 0,
						}),
						indicator: (_styles, context) => ({
							backgroundColor: context.theme.colors.primary.dark,
							backgroundTransparency: 0,
							strokeColor: context.theme.colors.primary.main,
							strokeTransparency: 1,
						}),
					}}
					disabled={disabled}
					width={prominent ? "100%" : 250}
				/>
			</Stack>
		);
	}
	if (control.kind === "slider") {
		const hero = control.emphasis === "hero";
		const nested = control.emphasis === "nested" || control.parent !== undefined;
		const intent = control.intent ?? "primary";
		const slider = (
			<Slider
				value={control.value}
				color={intent}
				min={control.min}
				max={control.max}
				step={control.step}
				disabled={disabled}
				fullWidth
				size={nested ? "sm" : "md"}
				tooltip={(value) => valueText(value, control.unit)}
				onChange={(value) => model.onValueChange(control.id, value, false)}
				onChangeEnd={(value) => model.onValueChange(control.id, value, true)}
				slotProps={{
					tooltip: { BackgroundColor3: Color3.fromRGB(42, 40, 41), BackgroundTransparency: 0 },
					tooltipStroke: { Color: Color3.fromRGB(67, 64, 65), Transparency: 0.2 },
					tooltipLabel: { TextColor3: Color3.fromRGB(244, 241, 240), TextTransparency: 0 },
					tooltipTail: { ImageColor3: Color3.fromRGB(42, 40, 41), ImageTransparency: 0 },
					tooltipTailBorder: { ImageColor3: Color3.fromRGB(67, 64, 65), ImageTransparency: 0.2 },
				}}
			/>
		);
		if (!hero) {
			return (
				<Stack width="100%" direction="horizontal" align="center" gap="sm">
					{nested && (
						<frame
							BackgroundTransparency={1}
							BorderSizePixel={0}
							Size={UDim2.fromOffset(HUB_THEME.spacing?.md ?? 12, 1)}
						/>
					)}
					{!hideLabel && (
						<Text
							text={control.label}
							size={nested ? "sm" : "md"}
							weight={nested ? 500 : 600}
							color={nested ? theme.text.secondary : theme.text.primary}
							width={nested ? 80 : 130}
							slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
						/>
					)}
					<frame BackgroundTransparency={1} BorderSizePixel={0} Size={new UDim2(0, 0, 0, 28)}>
						<uiflexitem FlexMode={Enum.UIFlexMode.Fill} />
						{slider}
					</frame>
					<Text
						text={valueText(control.value, control.unit)}
						size={nested ? "xs" : "sm"}
						weight={700}
						color={intentColor(intent)}
						width={64}
						slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Right } }}
					/>
				</Stack>
			);
		}
		return (
			<Stack width="100%" gap="md">
				<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween">
					{!hideLabel && <Text text={control.label} size="lg" weight={700} color={theme.text.primary} />}
					<Text text={valueText(control.value, control.unit)} size="xl" weight={700} color={intentColor(intent)} />
				</Stack>
				{slider}
				<Stack width="100%" direction="horizontal" justify="spaceBetween">
					<Text text={valueText(control.min, control.unit)} size="xs" color={theme.text.disabled} />
					<Text text={valueText(control.max, control.unit)} size="xs" color={theme.text.disabled} />
				</Stack>
			</Stack>
		);
	}

	if (control.kind === "toggle") {
		return (
			<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween" gap="md">
				<Text
					text={control.label}
					size="md"
					weight={600}
					color={disabled ? theme.text.disabled : theme.text.primary}
					width={compact ? 142 : 230}
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Stack direction="horizontal" align="center" justify="end" gap="sm" width={compact ? 44 : 190}>
					{control.keybind !== undefined && (
						<KeybindInput
							value={control.keybind}
							onChange={(value) => model.onValueChange(`${control.id}:keybind`, value, true)}
							disabled={disabled}
							clearable={false}
							size="sm"
							width={132}
						/>
					)}
					<Switch
						checked={control.value}
						onChange={(value) => model.onValueChange(control.id, value, true)}
						disabled={disabled}
						color="primary"
						size="md"
					/>
				</Stack>
			</Stack>
		);
	}

	if (control.kind === "keybind") {
		return (
			<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween" gap="md">
				<Stack gap="xs">
					<Text
						text={control.label}
						size="md"
						weight={600}
						color={disabled ? theme.text.disabled : theme.text.primary}
					/>
					<Text text="Click the keycap, then press a key" size="xs" color={theme.text.disabled} />
				</Stack>
				<EditableKeycap
					value={control.value}
					onChange={(value) => model.onValueChange(control.id, value, true)}
					disabled={disabled || control.readOnly === true}
				/>
			</Stack>
		);
	}

	if (control.kind === "model-viewer") return <frame BackgroundTransparency={1} BorderSizePixel={0} />;

	return (
		<Button
			label={control.label}
			variant={control.variant === "primary" ? "filled" : "outline"}
			color={control.variant === "danger" ? "error" : "primary"}
			disabled={disabled}
			fullWidth
			width="100%"
			onPress={() => model.onAction?.(control.action)}
		/>
	);
}
