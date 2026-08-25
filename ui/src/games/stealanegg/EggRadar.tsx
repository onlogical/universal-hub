import React from "@rbxts/react";
import { Icon } from "@prism/components/Icon";
import type { FarmMonitorEgg, FloatingMonitorModel } from "../../contracts";

function readableRarity(color: Color3): Color3 {
	const luminance = color.R * 0.299 + color.G * 0.587 + color.B * 0.114;
	return luminance < 0.28 ? color.Lerp(Color3.fromRGB(244, 247, 249), 0.55) : color;
}

function EggCard({ egg, order }: { readonly egg: FarmMonitorEgg; readonly order: number }): React.ReactElement {
	const rarity = readableRarity(egg.rarityColor);
	const sizeText = string.format("%.2f×", egg.size);
	const sizeFont = math.clamp(math.round(9 + egg.size * 3), 10, 18);
	const sizeColor = string.format("#%02X%02X%02X", math.round(rarity.R * 255), math.round(rarity.G * 255), math.round(rarity.B * 255));
	const status = egg.target ? "TARGET" : egg.secured ? "SECURED" : egg.state === "Slot" ? "AVAILABLE" : egg.state.upper();
	return (
		<frame LayoutOrder={order} Size={new UDim2(0.5, -5, 0, 52)} BackgroundColor3={Color3.fromRGB(27, 27, 30).Lerp(egg.rarityColor, egg.target ? 0.18 : 0.07)} BorderSizePixel={0}>
			<uicorner CornerRadius={new UDim(0, 7)} />
			<uistroke Color={rarity} Transparency={egg.target ? 0.28 : 0.78} Thickness={1} />
			<imagelabel Position={UDim2.fromOffset(7, 6)} Size={UDim2.fromOffset(40, 40)} BackgroundColor3={egg.rarityColor} BackgroundTransparency={0.82} BorderSizePixel={0} Image={egg.icon} ScaleType={Enum.ScaleType.Fit}>
				<uicorner CornerRadius={new UDim(0, 6)} />
			</imagelabel>
			<textlabel Position={UDim2.fromOffset(55, 7)} Size={new UDim2(1, -116, 0, 17)} BackgroundTransparency={1} Text={`<b>${egg.name}</b> <font size="${sizeFont}" color="${sizeColor}">(${sizeText})</font>`} RichText TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={12} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
			<textlabel Position={UDim2.fromOffset(55, 25)} Size={new UDim2(1, -116, 0, 15)} BackgroundTransparency={1} Text={`${egg.rarity} · ${egg.area}`} TextColor3={rarity} TextSize={10} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Left} TextTruncate={Enum.TextTruncate.AtEnd} />
			<textlabel Position={new UDim2(1, -58, 0, 8)} Size={UDim2.fromOffset(50, 34)} BackgroundTransparency={1} Text={status} TextColor3={egg.target ? rarity : Color3.fromRGB(145, 151, 158)} TextSize={9} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Right} TextWrapped />
		</frame>
	);
}

function EggGrid({ eggs, order }: { readonly eggs: readonly FarmMonitorEgg[]; readonly order: number }): React.ReactElement {
	return (
		<frame LayoutOrder={order} BackgroundTransparency={1} Size={new UDim2(1, 0, 0, math.ceil(eggs.size() / 2) * 60)}>
			<uigridlayout CellPadding={UDim2.fromOffset(10, 8)} CellSize={new UDim2(0.5, -5, 0, 52)} FillDirectionMaxCells={2} SortOrder={Enum.SortOrder.LayoutOrder} />
			{eggs.map((egg, index) => <EggCard key={`${egg.uid}-${index}`} egg={egg} order={index} />)}
		</frame>
	);
}

export function EggRadar({ monitor }: { readonly monitor?: FloatingMonitorModel }): React.ReactElement {
	const live = monitor?.eggs ?? [];
	const secured = monitor?.securedEggs ?? [];
	return (
		<frame AutomaticSize={Enum.AutomaticSize.Y} Size={new UDim2(1, 0, 0, 0)} BackgroundColor3={Color3.fromRGB(25, 25, 28)} BorderSizePixel={0}>
			<uicorner CornerRadius={new UDim(0, 8)} />
			<uistroke Color={Color3.fromRGB(65, 65, 70)} Transparency={0.4} Thickness={1} />
			<uipadding PaddingTop={new UDim(0, 14)} PaddingBottom={new UDim(0, 14)} PaddingLeft={new UDim(0, 14)} PaddingRight={new UDim(0, 14)} />
			<uilistlayout Padding={new UDim(0, 9)} SortOrder={Enum.SortOrder.LayoutOrder} />
			<frame LayoutOrder={1} Size={new UDim2(1, 0, 0, 38)} BackgroundTransparency={1}>
				<Icon name="egg" size={19} color={Color3.fromRGB(255, 118, 87)} position={UDim2.fromOffset(0, 1)} />
				<textlabel Position={UDim2.fromOffset(28, 0)} Size={new UDim2(1, -28, 0, 18)} BackgroundTransparency={1} Text="Egg Radar" TextColor3={Color3.fromRGB(244, 247, 249)} TextSize={15} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Left} />
				<textlabel Position={UDim2.fromOffset(28, 19)} Size={new UDim2(1, -28, 0, 15)} BackgroundTransparency={1} Text={monitor ? `${live.size()} live · ${monitor.targets} targets · ${monitor.players} players` : "Enable Auto Farm to begin live egg tracking"} TextColor3={Color3.fromRGB(153, 159, 166)} TextSize={11} Font={Enum.Font.BuilderSans} TextXAlignment={Enum.TextXAlignment.Left} />
			</frame>
			{live.size() > 0 ? <EggGrid eggs={live} order={2} /> : <textlabel LayoutOrder={2} Size={new UDim2(1, 0, 0, 46)} BackgroundColor3={Color3.fromRGB(30, 30, 33)} BorderSizePixel={0} Text="No live egg snapshot yet" TextColor3={Color3.fromRGB(145, 151, 158)} TextSize={12} Font={Enum.Font.BuilderSansMedium}><uicorner CornerRadius={new UDim(0, 6)} /></textlabel>}
			{secured.size() > 0 && (
				<React.Fragment>
					<textlabel LayoutOrder={3} Size={new UDim2(1, 0, 0, 18)} BackgroundTransparency={1} Text={`SECURED THIS RUN  ${secured.size()}`} TextColor3={Color3.fromRGB(153, 159, 166)} TextSize={10} Font={Enum.Font.BuilderSansBold} TextXAlignment={Enum.TextXAlignment.Left} />
					<EggGrid eggs={secured} order={4} />
				</React.Fragment>
			)}
		</frame>
	);
}
