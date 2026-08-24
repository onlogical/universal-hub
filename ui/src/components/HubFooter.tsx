import React from "@rbxts/react";
import { Stack } from "@prism/components/Stack";
import { Text } from "@prism/components/Text";
import type { FooterItem } from "../contracts";

const COLORS = {
	positive: Color3.fromRGB(82, 205, 138),
	warning: Color3.fromRGB(245, 184, 75),
	negative: Color3.fromRGB(255, 132, 74),
	neutral: Color3.fromRGB(150, 150, 158),
};

function SignalIcon({ color }: { readonly color: Color3 }): React.ReactElement {
	return (
		<frame Size={UDim2.fromOffset(16, 14)} BackgroundTransparency={1}>
			{[5, 9, 13].map((height, index) => (
				<frame
					key={tostring(height)}
					AnchorPoint={new Vector2(0, 1)}
					Position={new UDim2(0, index * 6, 1, 0)}
					Size={UDim2.fromOffset(4, height)}
					BackgroundColor3={color}
					BorderSizePixel={0}
				>
					<uicorner CornerRadius={new UDim(0, 2)} />
				</frame>
			))}
		</frame>
	);
}

export function HubFooter({ items }: { readonly items?: readonly FooterItem[] }): React.ReactElement {
	return (
		<frame
			Position={new UDim2(0, 0, 1, -34)}
			Size={new UDim2(1, 0, 0, 34)}
			BackgroundColor3={Color3.fromRGB(20, 20, 22)}
			BorderSizePixel={0}
		>
			<frame Size={new UDim2(1, 0, 0, 1)} BackgroundColor3={Color3.fromRGB(55, 55, 60)} BorderSizePixel={0} />
			<uipadding PaddingLeft={new UDim(0, 18)} PaddingRight={new UDim(0, 18)} />
			<Stack width="100%" height="100%" direction="horizontal" align="center" justify="end" gap="sm">
				{(items ?? []).map((item) => {
					const color = COLORS[item.tone ?? "neutral"];
					return (
						<Stack key={item.id} direction="horizontal" align="center" gap="xs">
							{item.icon === "signal" && <SignalIcon color={color} />}
							<Text text={`${item.label} ${item.value}`} size="xs" weight={700} color={color} />
						</Stack>
					);
				})}
			</Stack>
		</frame>
	);
}
