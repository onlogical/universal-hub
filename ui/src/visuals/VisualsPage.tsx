import React from "@rbxts/react";
import { Box, ColorPicker, MultiSelect, Popover, Stack, Switch, Text, colorToHex } from "@prism";
import { theme } from "@prism/theme";
import type {
	CharacterPreviewPaletteRelationship,
	CharacterPreviewPaletteTarget,
	MenuControl,
	MenuPage,
	UniversalHubMenuModel,
} from "../contracts";
import { ControlView } from "../components/ControlView";
import { ModelViewer } from "../preview/ModelViewer";
import { ViewportDummy } from "../preview/ViewportDummy";

function Segments({
	options,
	value,
	onChange,
}: {
	readonly options: readonly { value: string; label: string }[];
	readonly value: string;
	readonly onChange: (value: string) => void;
}): React.ReactElement {
	return (
		<frame BackgroundColor3={Color3.fromRGB(18, 18, 19)} BorderSizePixel={0} Size={new UDim2(1, 0, 0, 32)}>
			<uicorner CornerRadius={new UDim(0, 6)} />
			<uilistlayout FillDirection={Enum.FillDirection.Horizontal} SortOrder={Enum.SortOrder.LayoutOrder} />
			{options.map((option, index) => {
				const selected = option.value === value;
				return (
					<textbutton
						key={option.value}
						LayoutOrder={index}
						AutoButtonColor={false}
						BackgroundColor3={selected ? Color3.fromRGB(91, 39, 30) : Color3.fromRGB(18, 18, 19)}
						BackgroundTransparency={selected ? 0 : 1}
						BorderSizePixel={0}
						Font={Enum.Font.BuilderSansBold}
						Size={new UDim2(1 / options.size(), 0, 1, 0)}
						Text={option.label}
						TextColor3={selected ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(177, 188, 199)}
						TextSize={13}
						Event={{ Activated: () => onChange(option.value) }}
					>
						<uicorner CornerRadius={new UDim(0, 6)} />
					</textbutton>
				);
			})}
		</frame>
	);
}

function Details({
	controls,
	model,
}: {
	readonly controls: readonly MenuControl[];
	readonly model: UniversalHubMenuModel;
}): React.ReactElement {
	return (
		<frame BackgroundTransparency={1} Size={UDim2.fromOffset(200, 68)}>
			{controls.map(
				(control, index) =>
					control.kind === "toggle" && (
						<frame
							key={control.id}
							BackgroundTransparency={1}
							Position={UDim2.fromOffset(0, index * 34)}
							Size={new UDim2(1, 0, 0, 34)}
							ZIndex={51}
						>
							<Text
								text={control.label}
								size="xs"
								weight={500}
								color={theme.text.secondary}
								width={160}
								height={34}
								slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left, ZIndex: 52 } }}
							/>
							<Switch
								checked={control.value}
								onChange={(value) => model.onValueChange(control.id, value, true)}
								size="sm"
								position={new UDim2(1, 0, 0.5, 0)}
								anchor={new Vector2(1, 0.5)}
								slotProps={{ root: { ZIndex: 53 } }}
							/>
						</frame>
					),
			)}
		</frame>
	);
}

function Tile({
	control,
	details,
	model,
	order,
}: {
	readonly control: MenuControl;
	readonly details: readonly MenuControl[];
	readonly model: UniversalHubMenuModel;
	readonly order: number;
}): React.ReactElement {
	const [open, setOpen] = React.useState(false);
	if (control.kind !== "toggle") return <frame BackgroundTransparency={1} LayoutOrder={order} />;
	const hasDetails = details.size() > 0;
	return (
		<frame BackgroundColor3={Color3.fromRGB(31, 31, 34)} BorderSizePixel={0} LayoutOrder={order} ZIndex={open ? 40 : 1}>
			<uicorner CornerRadius={new UDim(0, 5)} />
			<Text
				text={control.label}
				size="sm"
				weight={600}
				color={theme.text.primary}
				position={UDim2.fromOffset(10, 0)}
				width={hasDetails ? 116 : 142}
				height={40}
				slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
			/>
			{hasDetails && (
				<Popover
					content={<Details controls={details} model={model} />}
					placement="bottom"
					align="end"
					triggerMode="click"
					closeOnOutsidePress
					opened={open}
					onOpenedChange={setOpen}
					position={new UDim2(1, -10, 0.5, 0)}
					anchor={new Vector2(1, 0.5)}
					width={22}
					height={22}
					zIndex={42}
				>
					<frame BackgroundColor3={Color3.fromRGB(31, 31, 34)} Size={UDim2.fromOffset(22, 22)} ZIndex={42}>
						<uicorner CornerRadius={new UDim(0, 4)} />
						<uistroke
							Color={open ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(68, 68, 73)}
							Transparency={open ? 0.18 : 0.4}
							Thickness={1}
						/>
						{[6, 11, 16].map((y, index) => (
							<React.Fragment key={tostring(y)}>
								<frame
									BackgroundColor3={open ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(103, 115, 126)}
									BackgroundTransparency={0.12}
									BorderSizePixel={0}
									Position={UDim2.fromOffset(5, y)}
									Size={UDim2.fromOffset(12, 1)}
									ZIndex={43}
								/>
								<frame
									BackgroundColor3={open ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(103, 115, 126)}
									BorderSizePixel={0}
									Position={UDim2.fromOffset(index === 1 ? 8 : 13, y - 1)}
									Size={UDim2.fromOffset(3, 3)}
									ZIndex={44}
								>
									<uicorner CornerRadius={new UDim(1, 0)} />
								</frame>
							</React.Fragment>
						))}
					</frame>
				</Popover>
			)}
			<Switch
				checked={control.value}
				onChange={(value) => model.onValueChange(control.id, value, true)}
				size="md"
				position={new UDim2(1, hasDetails ? -42 : -10, 0.5, 0)}
				anchor={new Vector2(1, 0.5)}
			/>
		</frame>
	);
}

function Audience({
	controls,
	model,
	onOpenChange,
}: {
	readonly controls: readonly MenuControl[];
	readonly model: UniversalHubMenuModel;
	readonly onOpenChange: (opened: boolean) => void;
}): React.ReactElement {
	const toggles = controls.filter((control) => control.kind === "toggle");
	const value = toggles.filter((control) => control.value).map((control) => control.id);
	return (
		<MultiSelect
			options={toggles.map((control, index) => ({
				value: control.id,
				label: control.label,
				icon: index === 0 ? model.enemyAudienceIcon : model.allyAudienceIcon,
				iconColor: index === 0 ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(101, 157, 214),
			}))}
			value={value}
			onChange={(selected: readonly string[]) => {
				for (const control of toggles) {
					const enabled = selected.includes(control.id);
					if (enabled !== control.value) model.onValueChange(control.id, enabled, true);
				}
			}}
			onOpenedChange={onOpenChange}
			placeholder="Select visibility"
			maxSelectedLabels={2}
			maxVisibleOptions={2}
			fullWidth
			width={200}
			height={34}
			zIndex={80}
		/>
	);
}

function Preview({
	page,
	model,
	style,
	audience,
}: {
	readonly page: MenuPage;
	readonly model: UniversalHubMenuModel;
	readonly style?: MenuControl;
	readonly audience: readonly MenuControl[];
}): React.ReactElement {
	const [audienceOpen, setAudienceOpen] = React.useState(false);
	const preview = page.preview;
	const enabled = preview?.boxes || preview?.chams || preview?.names || preview?.health || preview?.weapon;
	return (
		<frame BackgroundTransparency={1} Size={new UDim2(1, 0, 0, 310)}>
			<Text
				text="ESP PREVIEW"
				size="xs"
				weight={800}
				color={theme.text.disabled}
				width={110}
				height={34}
				slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
			/>
			{style !== undefined && (
				<frame BackgroundTransparency={1} Position={new UDim2(1, -250, 0, 0)} Size={UDim2.fromOffset(250, 34)}>
					<ControlView control={style} model={model} hideLabel compact />
				</frame>
			)}
			{audience.size() > 0 && (
				<frame BackgroundTransparency={1} Position={UDim2.fromOffset(0, 42)} Size={new UDim2(1, 0, 0, 34)}>
					<Text text="VISIBILITY" size="xs" weight={800} color={theme.text.disabled} width={110} height={34} />
					<frame BackgroundTransparency={1} Position={new UDim2(1, -200, 0, 0)} Size={UDim2.fromOffset(200, 34)}>
						<Audience controls={audience} model={model} onOpenChange={setAudienceOpen} />
					</frame>
				</frame>
			)}
			<frame
				BackgroundColor3={Color3.fromRGB(18, 18, 19)}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(0, 84)}
				Size={new UDim2(1, 0, 0, 226)}
				ClipsDescendants
			>
				<uicorner CornerRadius={new UDim(0, 7)} />
				{enabled ? (
					<ViewportDummy preview={preview} suspended={audienceOpen} />
				) : (
					<Text text="Enable a visual to preview" size="sm" color={theme.text.disabled} width="100%" height={226} />
				)}
			</frame>
		</frame>
	);
}

function TargetPicker({
	relationship,
	target,
	model,
	checkerboardImage,
}: {
	readonly relationship: CharacterPreviewPaletteRelationship;
	readonly target: CharacterPreviewPaletteTarget;
	readonly model: UniversalHubMenuModel;
	readonly checkerboardImage?: string;
}): React.ReactElement {
	const fill = target.id === "fill";
	const alpha = fill ? (target.alpha ?? relationship.fillAlpha) : 1;
	const [color, setColor] = React.useState(target.color);
	const [draftAlpha, setDraftAlpha] = React.useState(alpha);
	React.useEffect(() => setColor(target.color), [target.color]);
	React.useEffect(() => setDraftAlpha(alpha), [alpha]);
	return (
		<ColorPicker
			value={color}
			alpha={draftAlpha}
			alphaEnabled={fill}
			onChange={setColor}
			onChangeEnd={(nextColor: Color3) => model.onValueChange(`espColor:${relationship.id}:${target.id}`, colorToHex(nextColor), true)}
			onAlphaChange={(nextAlpha: number) => setDraftAlpha(nextAlpha)}
			onAlphaChangeEnd={(nextAlpha: number) => fill && model.onValueChange(`espAlpha:${relationship.id}`, nextAlpha, true)}
			previousValue={target.defaultColor}
			previousAlpha={target.defaultAlpha ?? relationship.fillAlpha}
			checkerboardImage={checkerboardImage}
			placement="left"
			width={34}
			height={34}
			position={new UDim2(1, -42, 0, 1)}
			zIndex={100}
			slotProps={{ triggerLabel: { Visible: false } }}
		/>
	);
}

function Colors({ page, model }: { readonly page: MenuPage; readonly model: UniversalHubMenuModel }): React.ReactElement {
	const palette = page.preview?.palette;
	const [relationshipId, setRelationshipId] = React.useState("enemy");
	if (palette === undefined || palette.relationships.size() === 0)
		return <Text text="ESP colors are unavailable" size="sm" color={theme.text.disabled} />;
	const relationship =
		palette.relationships.find((candidate) => candidate.id === relationshipId) ?? palette.relationships[0];
	return (
		<Box width="100%" bg={theme.background.surface} radius="md" p="md" stroke={{ color: theme.border.subtle, thickness: 1 }}>
			<Stack width="100%" gap="sm">
				<Segments
					options={palette.relationships.map((candidate) => ({ value: candidate.id, label: candidate.label }))}
					value={relationship.id}
					onChange={setRelationshipId}
				/>
				{relationship.targets.map((target) => (
					<frame key={target.id} BackgroundColor3={Color3.fromRGB(31, 31, 34)} Size={new UDim2(1, 0, 0, 36)}>
						<uicorner CornerRadius={new UDim(0, 5)} />
						<Text text={target.label} size="sm" weight={600} color={theme.text.primary} position={UDim2.fromOffset(10, 0)} width={150} height={36} />
						<TargetPicker relationship={relationship} target={target} model={model} checkerboardImage={palette.checkerboardImage} />
					</frame>
				))}
				<textbutton
					AutoButtonColor={false}
					BackgroundColor3={Color3.fromRGB(91, 39, 30)}
					BorderSizePixel={0}
					Font={Enum.Font.BuilderSansBold}
					Size={new UDim2(1, 0, 0, 30)}
					Text="Reset All"
					TextColor3={Color3.fromRGB(255, 118, 87)}
					TextSize={13}
					Event={{ Activated: () => model.onValueChange("resetEspAll", true, true) }}
				/>
			</Stack>
		</Box>
	);
}

export function VisualsPage({
	page,
	model,
}: {
	readonly page: MenuPage;
	readonly model: UniversalHubMenuModel;
}): React.ReactElement {
	const [view, setView] = React.useState<"preview" | "colors">("preview");
	const grid = page.sections.find((section) => section.treatment === "grid");
	const style = page.sections.find((section) => section.treatment === "style");
	const extras = page.sections.filter((section) => section.treatment !== "grid" && section.treatment !== "style");
	const tiles =
		grid?.controls.filter(
			(control) => control.placement !== "details" && control.placement !== "audience",
		) ?? [];
	const detailsFor = (id: string) =>
		grid?.controls.filter((control) => control.placement === "details" && control.parent === id) ?? [];
	const audience = grid?.controls.filter((control) => control.placement === "audience") ?? [];
	const views = page.views ?? [];
	React.useEffect(() => {
		if (views.size() > 0 && views.find((candidate) => candidate.id === view) === undefined) setView(views[0].id);
	}, [views, view]);
	const rowCount = math.ceil(tiles.size() / 2);
	return (
		<Stack width="100%" gap="sm">
			{views.size() > 0 && (
				<Segments
					options={views.map((candidate) => ({ value: candidate.id, label: candidate.label }))}
					value={view}
					onChange={(nextView) => setView(nextView as "preview" | "colors")}
				/>
			)}
			{view === "colors" ? (
				<Colors page={page} model={model} />
			) : (
				<Box width="100%" bg={theme.background.surface} radius="md" p="md" stroke={{ color: theme.border.subtle, thickness: 1 }}>
					<Stack width="100%" gap="md">
						<Preview page={page} model={model} style={style?.controls[0]} audience={audience} />
						<frame BackgroundTransparency={1} Size={new UDim2(1, 0, 0, rowCount * 48)}>
							<uigridlayout CellPadding={UDim2.fromOffset(10, 8)} CellSize={new UDim2(0.5, -5, 0, 40)} FillDirectionMaxCells={2} SortOrder={Enum.SortOrder.LayoutOrder} />
							{tiles.map((control, index) => (
								<Tile key={control.id} control={control} details={detailsFor(control.id)} model={model} order={index} />
							))}
						</frame>
						{extras.map((section) => (
							<Stack key={section.id} width="100%" gap="md">
								<Text text={section.label} size="sm" weight={800} color={theme.text.secondary} width="100%" />
								{section.controls.map((control) =>
									control.kind === "model-viewer" ? (
										<ModelViewer key={control.id} control={control} />
									) : (
										<ControlView key={control.id} control={control} model={model} />
									),
								)}
							</Stack>
						))}
					</Stack>
				</Box>
			)}
		</Stack>
	);
}
