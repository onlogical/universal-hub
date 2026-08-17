import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Popover } from "@prism/components/Popover";
import { Slider } from "@prism/components/Slider";
import { Text } from "@prism/components/Text";

export * from "@prism/components/Box";
export * from "@prism/components/Button";
export * from "@prism/components/KeybindInput";
export * from "@prism/components/Modal";
export * from "@prism/components/Popover";
export * from "@prism/components/ScrollArea";
export * from "@prism/components/Select";
export * from "@prism/components/SegmentedControl";
export * from "@prism/components/Slider";
export * from "@prism/components/Stack";
export * from "@prism/components/Switch";
export * from "@prism/components/Tabs";
export * from "@prism/components/Text";
export * from "@prism/theme";

type SizeValue = number | string | UDim;

interface MultiSelectOption {
	readonly value: string;
	readonly label: string;
	readonly icon?: string;
	readonly iconColor?: Color3;
	readonly disabled?: boolean;
}

interface MultiSelectProps {
	readonly options: readonly MultiSelectOption[];
	readonly value: readonly string[];
	readonly onChange?: (value: readonly string[]) => void;
	readonly onOpenedChange?: (opened: boolean) => void;
	readonly placeholder?: string;
	readonly disabled?: boolean;
	readonly width?: SizeValue;
	readonly height?: SizeValue;
	readonly position?: UDim2;
	readonly zIndex?: number;
	readonly maxSelectedLabels?: number;
	readonly maxVisibleOptions?: number;
	readonly size?: string;
	readonly fullWidth?: boolean;
}

function contains(values: readonly string[], value: string): boolean {
	return values.find((entry) => entry === value) !== undefined;
}

export function MultiSelect(props: MultiSelectProps): React.ReactElement {
	const selectedLabels = props.options
		.filter((option) => contains(props.value, option.value))
		.map((option) => option.label);
	const label = selectedLabels.size() === 0 ? (props.placeholder ?? "Select") : selectedLabels.join(", ");
	const toggle = (option: MultiSelectOption) => {
		if (props.disabled || option.disabled) return;
		const nextValues = contains(props.value, option.value)
			? props.value.filter((entry) => entry !== option.value)
			: [...props.value, option.value];
		props.onChange?.(nextValues);
	};
	return (
		<Popover
			content={
				<frame
					BackgroundTransparency={1}
					BorderSizePixel={0}
					AutomaticSize={Enum.AutomaticSize.Y}
					Size={UDim2.fromOffset(190, 0)}
				>
					<uilistlayout Padding={new UDim(0, 4)} SortOrder={Enum.SortOrder.LayoutOrder} />
					{props.options.map((option, index) => {
						const selected = contains(props.value, option.value);
						return (
							<textbutton
								key={option.value}
								LayoutOrder={index}
								AutoButtonColor={false}
								BackgroundColor3={selected ? Color3.fromRGB(91, 39, 30) : Color3.fromRGB(31, 31, 34)}
								BorderSizePixel={0}
								Font={Enum.Font.BuilderSans}
								Size={UDim2.fromOffset(190, 32)}
								Text={`${selected ? "✓  " : "    "}${option.label}`}
								TextColor3={option.disabled ? Color3.fromRGB(103, 115, 126) : Color3.fromRGB(244, 247, 249)}
								TextSize={14}
								TextXAlignment={Enum.TextXAlignment.Left}
								Event={{ Activated: () => toggle(option) }}
							>
								<uicorner CornerRadius={new UDim(0, 5)} />
								<uipadding PaddingLeft={new UDim(0, 10)} />
							</textbutton>
						);
					})}
				</frame>
			}
			placement="bottom"
			align="end"
			triggerMode="click"
			closeOnOutsidePress
			disabled={props.disabled}
			onOpenedChange={props.onOpenedChange}
			width={props.width}
			height={props.height}
			position={props.position}
			zIndex={props.zIndex}
		>
			<Button label={label} variant="outline" color="secondary" fullWidth width="100%" />
		</Popover>
	);
}

interface ColorPickerProps {
	readonly value: Color3;
	readonly alpha?: number;
	readonly alphaEnabled?: boolean;
	readonly onChange?: (value: Color3) => void;
	readonly onChangeEnd?: (value: Color3) => void;
	readonly onAlphaChange?: (value: number) => void;
	readonly onAlphaChangeEnd?: (value: number) => void;
	readonly previousValue?: Color3;
	readonly previousAlpha?: number;
	readonly onReset?: () => void;
	readonly onOpenedChange?: (opened: boolean) => void;
	readonly width?: SizeValue;
	readonly height?: SizeValue;
	readonly position?: UDim2;
	readonly zIndex?: number;
	readonly placement?: "top" | "bottom" | "left" | "right";
	readonly align?: "start" | "center" | "end";
	readonly checkerboardImage?: string;
	readonly styleOverrides?: unknown;
	readonly slotProps?: unknown;
}

function withChannel(color: Color3, channel: "r" | "g" | "b", value: number): Color3 {
	return Color3.fromRGB(
		math.floor((channel === "r" ? value : color.R) * 255 + 0.5),
		math.floor((channel === "g" ? value : color.G) * 255 + 0.5),
		math.floor((channel === "b" ? value : color.B) * 255 + 0.5),
	);
}

function channelRow(
	label: string,
	value: number,
	onChange: (value: number) => void,
	onChangeEnd: (value: number) => void,
): React.ReactElement {
	return (
		<frame BackgroundTransparency={1} BorderSizePixel={0} Size={UDim2.fromOffset(220, 32)}>
			<Text text={label} size="xs" width={24} height={32} />
			<Slider
				value={value}
				min={0}
				max={1}
				step={1 / 255}
				onChange={onChange}
				onChangeEnd={onChangeEnd}
				position={UDim2.fromOffset(30, 0)}
				width={180}
				height={32}
			/>
		</frame>
	);
}

export function ColorPicker(props: ColorPickerProps): React.ReactElement {
	const update = (channel: "r" | "g" | "b", value: number) => props.onChange?.(withChannel(props.value, channel, value));
	const commit = (channel: "r" | "g" | "b", value: number) =>
		props.onChangeEnd?.(withChannel(props.value, channel, value));
	return (
		<Popover
			content={
				<frame
					BackgroundTransparency={1}
					BorderSizePixel={0}
					AutomaticSize={Enum.AutomaticSize.Y}
					Size={UDim2.fromOffset(220, 0)}
				>
					<uilistlayout Padding={new UDim(0, 4)} SortOrder={Enum.SortOrder.LayoutOrder} />
					{channelRow("R", props.value.R, (value) => update("r", value), (value) => commit("r", value))}
					{channelRow("G", props.value.G, (value) => update("g", value), (value) => commit("g", value))}
					{channelRow("B", props.value.B, (value) => update("b", value), (value) => commit("b", value))}
					{props.alphaEnabled &&
						channelRow(
							"A",
							props.alpha ?? 1,
							(value) => props.onAlphaChange?.(value),
							(value) => props.onAlphaChangeEnd?.(value),
						)}
					{props.onReset !== undefined && (
						<Button label="Reset" variant="outline" color="secondary" fullWidth onPress={props.onReset} />
					)}
				</frame>
			}
			placement={props.placement}
			align={props.align}
			triggerMode="click"
			closeOnOutsidePress
			onOpenedChange={props.onOpenedChange}
			width={props.width}
			height={props.height}
			position={props.position}
			zIndex={props.zIndex}
		>
			<frame BackgroundColor3={props.value} BorderSizePixel={0} Size={UDim2.fromScale(1, 1)}>
				<uicorner CornerRadius={new UDim(0, 5)} />
				<uistroke Color={Color3.fromRGB(103, 115, 126)} Transparency={0.15} Thickness={1} />
			</frame>
		</Popover>
	);
}

export function colorToHex(color: Color3): string {
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5));
}
