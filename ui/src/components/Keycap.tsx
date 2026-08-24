import React from "@rbxts/react";
import { KeybindInput } from "@prism/components/KeybindInput";
import { Text } from "@prism/components/Text";
import { theme } from "@prism/theme";

function keycapLabel(value: Enum.KeyCode | Enum.UserInputType): string {
	if (value === Enum.KeyCode.LeftShift || value === Enum.KeyCode.RightShift) return "↑  Shift";
	if (value === Enum.KeyCode.LeftControl || value === Enum.KeyCode.RightControl) return "⌃  Ctrl";
	if (value === Enum.KeyCode.LeftAlt || value === Enum.KeyCode.RightAlt) return "⌥  Alt";
	if (value === Enum.KeyCode.Return || value === Enum.KeyCode.KeypadEnter) return "↵  Enter";
	if (value === Enum.KeyCode.Backspace) return "⌫  Backspace";
	if (value === Enum.KeyCode.Tab) return "⇥  Tab";
	if (value === Enum.KeyCode.Space) return "Space";
	return value.Name;
}

function keycapWidth(value: Enum.KeyCode | Enum.UserInputType, capturing: boolean): number {
	if (capturing) return 112;
	if (value === Enum.KeyCode.Space) return 132;
	if (
		value === Enum.KeyCode.LeftShift ||
		value === Enum.KeyCode.RightShift ||
		value === Enum.KeyCode.LeftControl ||
		value === Enum.KeyCode.RightControl ||
		value === Enum.KeyCode.LeftAlt ||
		value === Enum.KeyCode.RightAlt ||
		value === Enum.KeyCode.Return ||
		value === Enum.KeyCode.KeypadEnter ||
		value === Enum.KeyCode.Backspace
	)
		return 104;
	const label = keycapLabel(value);
	return label.size() <= 2 ? 46 : math.clamp(label.size() * 8 + 22, 62, 118);
}

export function EditableKeycap({
	value,
	onChange,
	disabled,
}: {
	readonly value: Enum.KeyCode | Enum.UserInputType;
	readonly onChange: (value: Enum.KeyCode | Enum.UserInputType) => void;
	readonly disabled: boolean;
}): React.ReactElement {
	const [capturing, setCapturing] = React.useState(false);
	const [hovered, setHovered] = React.useState(false);
	const width = keycapWidth(value, capturing);
	const topY = hovered && !capturing ? 6 : 7;
	const face = hovered && !capturing ? Color3.fromRGB(52, 49, 51) : Color3.fromRGB(44, 42, 44);
	const faceEdge = capturing
		? Color3.fromRGB(255, 118, 87)
		: hovered
			? Color3.fromRGB(105, 99, 102)
			: Color3.fromRGB(82, 77, 80);
	return (
		<frame BackgroundTransparency={1} BorderSizePixel={0} Size={UDim2.fromOffset(width, 48)}>
			<frame
				BackgroundColor3={Color3.fromRGB(9, 9, 10)}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(0, 7)}
				Size={UDim2.fromOffset(width, 40)}
			>
				<uicorner CornerRadius={new UDim(0, 8)} />
				<uistroke Color={Color3.fromRGB(55, 52, 54)} Transparency={0.24} Thickness={1} />
			</frame>
			<frame
				BackgroundColor3={Color3.fromRGB(25, 24, 26)}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(2, 4)}
				Size={UDim2.fromOffset(width - 4, 38)}
			>
				<uicorner CornerRadius={new UDim(0, 7)} />
				<frame
					BackgroundColor3={Color3.fromRGB(6, 6, 7)}
					BackgroundTransparency={0.15}
					BorderSizePixel={0}
					Position={new UDim2(0, 5, 1, -5)}
					Size={new UDim2(1, -10, 0, 5)}
				>
					<uicorner CornerRadius={new UDim(0, 3)} />
				</frame>
			</frame>
			<frame
				BackgroundColor3={face}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(2, topY)}
				Size={UDim2.fromOffset(width - 4, 33)}
			>
				<uicorner CornerRadius={new UDim(0, 6)} />
				<uistroke Color={faceEdge} Transparency={0.03} Thickness={capturing ? 1.5 : 1} />
				<frame
					BackgroundColor3={Color3.fromRGB(255, 255, 255)}
					BackgroundTransparency={capturing ? 0.84 : 0.9}
					BorderSizePixel={0}
					Position={UDim2.fromOffset(8, 2)}
					Size={new UDim2(1, -16, 0, 1)}
				/>
				<Text
					text={capturing ? "Press a key…" : keycapLabel(value)}
					size="md"
					weight={800}
					color={theme.text.primary}
					width="100%"
					height={33}
				/>
			</frame>
			<KeybindInput
				value={value}
				onChange={onChange}
				onCapturingChange={setCapturing}
				captureDevice="keyboard"
				clearable={false}
				disabled={disabled}
				width={width}
				height={48}
				position={UDim2.fromOffset(0, 0)}
				Event={{ MouseEnter: () => setHovered(true), MouseLeave: () => setHovered(false) }}
				slotProps={{
					trigger: { BackgroundTransparency: 1, ZIndex: 10 },
					triggerStroke: { Transparency: 1 },
					content: { Visible: false },
				}}
			/>
		</frame>
	);
}
