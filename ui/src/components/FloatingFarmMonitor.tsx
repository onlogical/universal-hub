import React from "@rbxts/react";
import { Icon } from "@prism/components/Icon";
import type { FloatingMonitorModel } from "../contracts";

const UserInputService = game.GetService("UserInputService");
const Workspace = game.GetService("Workspace");
const TweenService = game.GetService("TweenService");

function readableRarity(color: Color3): Color3 {
	const luminance = color.R * 0.299 + color.G * 0.587 + color.B * 0.114;
	return luminance < 0.28 ? color.Lerp(Color3.fromRGB(244, 247, 249), 0.55) : color;
}

function Metric({
	icon,
	value,
}: {
	readonly icon: "egg" | "target" | "users";
	readonly value: string;
}): React.ReactElement {
	return (
		<frame Size={new UDim2(0.333, -5, 1, 0)} BackgroundTransparency={1}>
			<uilistlayout
				FillDirection={Enum.FillDirection.Horizontal}
				VerticalAlignment={Enum.VerticalAlignment.Center}
				Padding={new UDim(0, 7)}
			/>
			<Icon name={icon} size={17} color={Color3.fromRGB(177, 188, 199)} layoutOrder={1} />
			<textlabel
				LayoutOrder={2}
				Size={UDim2.fromOffset(44, 24)}
				BackgroundTransparency={1}
				Text={value}
				TextColor3={Color3.fromRGB(244, 247, 249)}
				TextSize={14}
				Font={Enum.Font.BuilderSansBold}
				TextXAlignment={Enum.TextXAlignment.Left}
			/>
		</frame>
	);
}

export function FloatingFarmMonitor({ monitor }: { readonly monitor?: FloatingMonitorModel }): React.ReactElement {
	const panelRef = React.useRef<CanvasGroup>();
	const dragRef = React.useRef<{ pointer: Vector2; start: Vector2; touch?: InputObject }>();
	const [position, setPosition] = React.useState(UDim2.fromOffset(24, 132));
	const [collapsed, setCollapsed] = React.useState(false);

	React.useEffect(() => {
		const move = UserInputService.InputChanged.Connect((input) => {
			const drag = dragRef.current;
			if (drag === undefined) return;
			if (drag.touch !== undefined ? input !== drag.touch : input.UserInputType !== Enum.UserInputType.MouseMovement) return;
			const panel = panelRef.current;
			if (panel === undefined) return;
			const viewport = Workspace.CurrentCamera?.ViewportSize ?? new Vector2(1920, 1080);
			const delta = new Vector2(input.Position.X, input.Position.Y).sub(drag.pointer);
			setPosition(
				UDim2.fromOffset(
					math.clamp(drag.start.X + delta.X, 8, math.max(8, viewport.X - panel.AbsoluteSize.X - 8)),
					math.clamp(drag.start.Y + delta.Y, 8, math.max(8, viewport.Y - panel.AbsoluteSize.Y - 8)),
				),
			);
		});
		const finish = UserInputService.InputEnded.Connect((input) => {
			const drag = dragRef.current;
			if (
				drag !== undefined &&
				((drag.touch === undefined && input.UserInputType === Enum.UserInputType.MouseButton1) || input === drag.touch)
			)
				dragRef.current = undefined;
		});
		return () => {
			move.Disconnect();
			finish.Disconnect();
		};
	}, []);

	React.useEffect(() => {
		const panel = panelRef.current;
		if (panel === undefined || monitor?.visible !== true) return;
		panel.GroupTransparency = 1;
		const tween = TweenService.Create(
			panel,
			new TweenInfo(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ GroupTransparency: 0 },
		);
		tween.Play();
		return () => tween.Cancel();
	}, [monitor?.visible]);

	if (monitor?.visible !== true) return <></>;
	const height = collapsed ? 52 : 390;
	const canvasHeight = monitor.eggs.size() * 44;
	const beginDrag = (input: InputObject) => {
		if (input.UserInputType !== Enum.UserInputType.MouseButton1 && input.UserInputType !== Enum.UserInputType.Touch) return;
		const panel = panelRef.current;
		if (panel === undefined) return;
		dragRef.current = {
			pointer: new Vector2(input.Position.X, input.Position.Y),
			start: new Vector2(panel.AbsolutePosition.X, panel.AbsolutePosition.Y),
			touch: input.UserInputType === Enum.UserInputType.Touch ? input : undefined,
		};
	};

	return (
		<canvasgroup
			ref={panelRef}
			Position={position}
			Size={UDim2.fromOffset(376, height)}
			BackgroundColor3={Color3.fromRGB(20, 20, 22)}
			BorderSizePixel={0}
			ZIndex={90}
			ClipsDescendants
		>
			<uicorner CornerRadius={new UDim(0, 10)} />
			<uistroke Color={Color3.fromRGB(68, 68, 73)} Transparency={0.25} Thickness={1} />
			<frame
				Active
				Size={new UDim2(1, 0, 0, 52)}
				BackgroundColor3={Color3.fromRGB(24, 24, 26)}
				BorderSizePixel={0}
				Event={{ InputBegan: (_frame, input) => beginDrag(input) }}
			>
				<uipadding PaddingLeft={new UDim(0, 14)} PaddingRight={new UDim(0, 10)} />
				<frame Position={UDim2.fromOffset(0, 15)} Size={UDim2.fromOffset(7, 7)} BackgroundColor3={Color3.fromRGB(98, 214, 173)} BorderSizePixel={0}>
					<uicorner CornerRadius={new UDim(1, 0)} />
				</frame>
				<textlabel Position={UDim2.fromOffset(14, 7)} Size={new UDim2(1, -54, 0, 18)} BackgroundTransparency={1} Text="Auto Farm" TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={15} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Left} />
				<textlabel Position={UDim2.fromOffset(14, 26)} Size={new UDim2(1, -54, 0, 15)} BackgroundTransparency={1} Text={monitor.stage} TextColor3={Color3.fromRGB(177, 188, 199)} TextSize={12} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
				<textbutton Position={new UDim2(1, -32, 0, 10)} Size={UDim2.fromOffset(28, 28)} BackgroundTransparency={1} BorderSizePixel={0} Text={collapsed ? "+" : "−"} TextColor3={Color3.fromRGB(177, 188, 199)} TextSize={20} Font={Enum.Font.BuilderSansBold} Event={{ Activated: () => setCollapsed(!collapsed) }} />
			</frame>
			{!collapsed && (
				<frame Position={UDim2.fromOffset(0, 52)} Size={new UDim2(1, 0, 1, -52)} BackgroundTransparency={1}>
					<textlabel Position={UDim2.fromOffset(14, 12)} Size={new UDim2(1, -28, 0, 34)} BackgroundTransparency={1} Text={monitor.detail} TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={13} Font={Enum.Font.BuilderSansMedium} TextWrapped TextXAlignment={Enum.TextXAlignment.Left} TextYAlignment={Enum.TextYAlignment.Top} />
					<frame Position={UDim2.fromOffset(14, 54)} Size={new UDim2(1, -28, 0, 34)} BackgroundTransparency={1}>
						<uilistlayout FillDirection={Enum.FillDirection.Horizontal} Padding={new UDim(0, 8)} />
						<Metric icon="egg" value={tostring(monitor.eggs.size())} />
						<Metric icon="target" value={tostring(monitor.targets)} />
						<Metric icon="users" value={tostring(monitor.players)} />
					</frame>
					<frame Position={UDim2.fromOffset(14, 98)} Size={new UDim2(1, -28, 0, 1)} BackgroundColor3={Color3.fromRGB(48, 48, 52)} BorderSizePixel={0} />
					<scrollingframe Position={UDim2.fromOffset(8, 110)} Size={new UDim2(1, -16, 1, -118)} BackgroundTransparency={1} BorderSizePixel={0} ScrollBarThickness={3} ScrollBarImageColor3={Color3.fromRGB(101, 101, 108)} CanvasSize={UDim2.fromOffset(0, canvasHeight)}>
						<uilistlayout Padding={new UDim(0, 2)} SortOrder={Enum.SortOrder.LayoutOrder} />
						{monitor.eggs.map((egg, index) => {
							const rarity = readableRarity(egg.rarityColor);
							const surface = Color3.fromRGB(24, 24, 26).Lerp(egg.rarityColor, egg.target ? 0.2 : 0.09);
							return (
								<frame key={egg.uid} LayoutOrder={index} Size={new UDim2(1, -4, 0, 42)} BackgroundColor3={surface} BackgroundTransparency={0.08} BorderSizePixel={0}>
									<uicorner CornerRadius={new UDim(0, 6)} />
									<uistroke Color={rarity} Transparency={egg.target ? 0.3 : 0.78} Thickness={1} />
									<imagelabel Position={UDim2.fromOffset(7, 5)} Size={UDim2.fromOffset(32, 32)} BackgroundColor3={egg.rarityColor} BackgroundTransparency={0.82} BorderSizePixel={0} Image={egg.icon} ScaleType={Enum.ScaleType.Fit}>
										<uicorner CornerRadius={new UDim(0, 5)} />
									</imagelabel>
									<textlabel Position={UDim2.fromOffset(47, 5)} Size={new UDim2(1, -141, 0, 16)} BackgroundTransparency={1} Text={egg.name} TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={12} Font={Enum.Font.BuilderSansMedium} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
									<textlabel Position={UDim2.fromOffset(47, 21)} Size={new UDim2(1, -141, 0, 14)} BackgroundTransparency={1} Text={`${egg.rarity} · ${egg.area}`} TextColor3={rarity} TextSize={10} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
									<textlabel Position={new UDim2(1, -88, 0, 7)} Size={UDim2.fromOffset(78, 28)} BackgroundTransparency={1} Text={`${string.format("%.2f", egg.size)}x  ${egg.state}`} TextColor3={Color3.fromRGB(177, 188, 199)} TextSize={10} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Right} />
								</frame>
							);
						})}
					</scrollingframe>
				</frame>
			)}
		</canvasgroup>
	);
}
