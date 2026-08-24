import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Popover } from "@prism/components/Popover";
import { Slider } from "@prism/components/Slider";
import { Text } from "@prism/components/Text";

const UserInputService = game.GetService("UserInputService");

export interface EspColorPickerProps {
	readonly value: Color3;
	readonly alpha?: number;
	readonly alphaEnabled?: boolean;
	readonly onChange: (value: Color3) => void;
	readonly onChangeEnd: (value: Color3) => void;
	readonly onAlphaChange?: (value: number) => void;
	readonly onAlphaChangeEnd?: (value: number) => void;
	readonly previousValue: Color3;
	readonly previousAlpha?: number;
	readonly checkerboardImage?: string;
	readonly width?: number | string | UDim;
	readonly height?: number | string | UDim;
	readonly position?: UDim2;
	readonly zIndex?: number;
}

export function colorToHex(color: Color3): string {
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
	);
}

function SaturationValue({
	hue,
	saturation,
	value,
	onChange,
	onChangeEnd,
}: {
	readonly hue: number;
	readonly saturation: number;
	readonly value: number;
	readonly onChange: (color: Color3) => void;
	readonly onChangeEnd: (color: Color3) => void;
}): React.ReactElement {
	const ref = React.useRef<Frame>();
	const dragging = React.useRef<InputObject>();
	const colorFromInput = (input: InputObject) => {
		const frame = ref.current;
		if (frame === undefined) return Color3.fromHSV(hue, saturation, value);
		const x = math.clamp((input.Position.X - frame.AbsolutePosition.X) / frame.AbsoluteSize.X, 0, 1);
		const y = math.clamp((input.Position.Y - frame.AbsolutePosition.Y) / frame.AbsoluteSize.Y, 0, 1);
		return Color3.fromHSV(hue, x, 1 - y);
	};
	React.useEffect(() => {
		const changed = UserInputService.InputChanged.Connect((input) => {
			if (
				dragging.current !== undefined &&
				(input === dragging.current || input.UserInputType === Enum.UserInputType.MouseMovement)
			)
				onChange(colorFromInput(input));
		});
		const ended = UserInputService.InputEnded.Connect((input) => {
			if (
				dragging.current !== undefined &&
				(input === dragging.current || input.UserInputType === Enum.UserInputType.MouseButton1)
			) {
				onChangeEnd(colorFromInput(input));
				dragging.current = undefined;
			}
		});
		return () => {
			changed.Disconnect();
			ended.Disconnect();
		};
	}, [hue, saturation, value, onChange, onChangeEnd]);

	return (
		<frame
			ref={ref}
			BackgroundColor3={Color3.fromHSV(hue, 1, 1)}
			BorderSizePixel={0}
			Size={UDim2.fromOffset(220, 132)}
			Event={{
				InputBegan: (_, input) => {
					if (
						input.UserInputType === Enum.UserInputType.MouseButton1 ||
						input.UserInputType === Enum.UserInputType.Touch
					) {
						dragging.current = input;
						onChange(colorFromInput(input));
					}
				},
			}}
		>
			<uicorner CornerRadius={new UDim(0, 5)} />
			<frame BackgroundColor3={Color3.fromRGB(255, 255, 255)} BorderSizePixel={0} Size={UDim2.fromScale(1, 1)}>
				<uigradient
					Color={new ColorSequence(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255))}
					Transparency={new NumberSequence(0, 1)}
				/>
				<frame BackgroundColor3={Color3.fromRGB(0, 0, 0)} BorderSizePixel={0} Size={UDim2.fromScale(1, 1)}>
					<uigradient Rotation={90} Transparency={new NumberSequence(1, 0)} />
				</frame>
			</frame>
			<frame
				AnchorPoint={new Vector2(0.5, 0.5)}
				BackgroundColor3={Color3.fromHSV(hue, saturation, value)}
				BorderSizePixel={0}
				Position={UDim2.fromScale(saturation, 1 - value)}
				Size={UDim2.fromOffset(12, 12)}
			>
				<uicorner CornerRadius={new UDim(1, 0)} />
				<uistroke Color={Color3.fromRGB(255, 255, 255)} Thickness={2} />
			</frame>
		</frame>
	);
}

function SliderRow({
	label,
	value,
	onChange,
	onChangeEnd,
}: {
	readonly label: string;
	readonly value: number;
	readonly onChange: (value: number) => void;
	readonly onChangeEnd: (value: number) => void;
}): React.ReactElement {
	return (
		<frame BackgroundTransparency={1} BorderSizePixel={0} Size={UDim2.fromOffset(220, 28)}>
			<Text text={label} size="xs" width={24} height={28} />
			<Slider value={value} min={0} max={1} step={1 / 255} onChange={onChange} onChangeEnd={onChangeEnd} position={UDim2.fromOffset(30, 0)} width={180} height={28} />
		</frame>
	);
}

export function EspColorPicker(props: EspColorPickerProps): React.ReactElement {
	const [hue, saturation, value] = props.value.ToHSV();
	const updateHue = (nextHue: number) => props.onChange(Color3.fromHSV(nextHue, saturation, value));
	const commitHue = (nextHue: number) => props.onChangeEnd(Color3.fromHSV(nextHue, saturation, value));
	const reset = () => {
		props.onChange(props.previousValue);
		props.onChangeEnd(props.previousValue);
		if (props.alphaEnabled && props.previousAlpha !== undefined) {
			props.onAlphaChange?.(props.previousAlpha);
			props.onAlphaChangeEnd?.(props.previousAlpha);
		}
	};

	return (
		<Popover
			content={
				<frame BackgroundTransparency={1} BorderSizePixel={0} AutomaticSize={Enum.AutomaticSize.Y} Size={UDim2.fromOffset(220, 0)}>
					<uilistlayout Padding={new UDim(0, 6)} SortOrder={Enum.SortOrder.LayoutOrder} />
					<SaturationValue hue={hue} saturation={saturation} value={value} onChange={props.onChange} onChangeEnd={props.onChangeEnd} />
					<SliderRow label="H" value={hue} onChange={updateHue} onChangeEnd={commitHue} />
					{props.alphaEnabled && (
						<SliderRow label="A" value={props.alpha ?? 1} onChange={(alpha) => props.onAlphaChange?.(alpha)} onChangeEnd={(alpha) => props.onAlphaChangeEnd?.(alpha)} />
					)}
					<Button label="Reset" variant="outline" color="secondary" fullWidth onPress={reset} />
				</frame>
			}
			placement="left"
			align="center"
			triggerMode="click"
			closeOnOutsidePress
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
