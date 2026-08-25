import React from "@rbxts/react";
import type { FloatingMonitorModel } from "../contracts";

const UserInputService = game.GetService("UserInputService");
const Workspace = game.GetService("Workspace");
const TweenService = game.GetService("TweenService");

function readableRarity(color: Color3): Color3 {
	const luminance = color.R * 0.299 + color.G * 0.587 + color.B * 0.114;
	return luminance < 0.28 ? color.Lerp(Color3.fromRGB(244, 247, 249), 0.55) : color;
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
			new TweenInfo(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ GroupTransparency: 0 },
		);
		tween.Play();
		return () => tween.Cancel();
	}, [monitor?.visible]);

	if (monitor?.visible !== true) return <></>;
	const activeTarget = monitor.eggs.find((egg) => egg.target === true);
	const target = activeTarget ?? monitor.eggs.find((egg) => egg.eligible === true);
	const rarity = target ? readableRarity(target.rarityColor) : Color3.fromRGB(177, 188, 199);
	const sizeFont = target ? math.clamp(math.round(10 + target.size * 3), 11, 18) : 12;
	const sizeColor = string.format("#%02X%02X%02X", math.round(rarity.R * 255), math.round(rarity.G * 255), math.round(rarity.B * 255));
	const targetTitle = target
		? `<b>${target.name}</b> <font size="${sizeFont}" color="${sizeColor}">(${string.format("%.2f×", target.size)})</font>`
		: "Waiting for an egg";
	const secured = monitor.securedEggs?.size() ?? 0;
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
			Size={UDim2.fromOffset(320, collapsed ? 48 : 178)}
			BackgroundColor3={Color3.fromRGB(20, 20, 22)}
			BorderSizePixel={0}
			ZIndex={90}
			ClipsDescendants
		>
			<uicorner CornerRadius={new UDim(0, 9)} />
			<uistroke Color={Color3.fromRGB(68, 68, 73)} Transparency={0.3} Thickness={1} />
			<frame Active Size={new UDim2(1, 0, 0, 48)} BackgroundColor3={Color3.fromRGB(25, 25, 27)} BorderSizePixel={0} Event={{ InputBegan: (_frame, input) => beginDrag(input) }}>
				<uipadding PaddingLeft={new UDim(0, 13)} PaddingRight={new UDim(0, 9)} />
				<frame Position={UDim2.fromOffset(0, 14)} Size={UDim2.fromOffset(7, 7)} BackgroundColor3={Color3.fromRGB(98, 214, 173)} BorderSizePixel={0}><uicorner CornerRadius={new UDim(1, 0)} /></frame>
				<textlabel Position={UDim2.fromOffset(14, 6)} Size={new UDim2(1, -50, 0, 17)} BackgroundTransparency={1} Text="Auto Farm" TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={14} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Left} />
				<textlabel Position={UDim2.fromOffset(14, 23)} Size={new UDim2(1, -50, 0, 15)} BackgroundTransparency={1} Text={monitor.stage} TextColor3={Color3.fromRGB(177, 188, 199)} TextSize={11} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
				<textbutton Position={new UDim2(1, -29, 0, 9)} Size={UDim2.fromOffset(26, 26)} BackgroundTransparency={1} BorderSizePixel={0} Text={collapsed ? "+" : "−"} TextColor3={Color3.fromRGB(177, 188, 199)} TextSize={18} Font={Enum.Font.BuilderSansBold} Event={{ Activated: () => setCollapsed(!collapsed) }} />
			</frame>
			{!collapsed && (
				<frame Position={UDim2.fromOffset(0, 48)} Size={new UDim2(1, 0, 1, -48)} BackgroundTransparency={1}>
					<imagelabel Position={UDim2.fromOffset(13, 14)} Size={UDim2.fromOffset(58, 58)} BackgroundColor3={target?.rarityColor ?? Color3.fromRGB(35, 35, 38)} BackgroundTransparency={0.78} BorderSizePixel={0} Image={target?.icon ?? ""} ScaleType={Enum.ScaleType.Fit}>
						<uicorner CornerRadius={new UDim(0, 8)} /><uistroke Color={rarity} Transparency={target ? 0.45 : 0.85} Thickness={1} />
					</imagelabel>
					<textlabel Position={UDim2.fromOffset(82, 12)} Size={new UDim2(1, -95, 0, 20)} BackgroundTransparency={1} Text={targetTitle} RichText TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={15} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
					<textlabel Position={UDim2.fromOffset(82, 32)} Size={new UDim2(1, -95, 0, 16)} BackgroundTransparency={1} Text={target ? `${target.reason ?? target.rarity} · ${target.area}` : "Watching global egg updates"} TextColor3={rarity} TextSize={11} Font={Enum.Font.BuilderSansMedium} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
					<textlabel Position={UDim2.fromOffset(82, 51)} Size={new UDim2(1, -95, 0, 31)} BackgroundTransparency={1} Text={monitor.detail} TextColor3={Color3.fromRGB(177, 188, 199)} TextSize={11} Font={Enum.Font.BuilderSans} TextWrapped TextXAlignment={Enum.TextXAlignment.Left} TextYAlignment={Enum.TextYAlignment.Top} TextTruncate={Enum.TextTruncate.AtEnd} />
					<frame Position={UDim2.fromOffset(13, 91)} Size={new UDim2(1, -26, 0, 1)} BackgroundColor3={Color3.fromRGB(48, 48, 52)} BorderSizePixel={0} />
					<frame Position={UDim2.fromOffset(13, 101)} Size={new UDim2(1, -26, 0, 22)} BackgroundTransparency={1}>
						<textlabel Size={new UDim2(1, 0, 1, 0)} BackgroundTransparency={1} Text={`${secured} EGG SECURED    ·    ${monitor.targets} TARGETS`} TextColor3={Color3.fromRGB(153, 159, 166)} TextSize={10} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Left} />
					</frame>
				</frame>
			)}
		</canvasgroup>
	);
}
