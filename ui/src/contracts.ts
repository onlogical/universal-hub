export type MenuValue = boolean | number | string | Enum.KeyCode | Enum.UserInputType;

export interface MenuOption {
	readonly value: string;
	readonly label: string;
	readonly disabled?: boolean;
}

interface ControlBase {
	readonly id: string;
	readonly label: string;
	readonly disabled?: boolean;
	readonly status?: "available" | "standby" | "unavailable";
	readonly parent?: string;
	readonly placement?: "grid" | "details" | "audience";
}

export interface SliderControl extends ControlBase {
	readonly kind: "slider";
	readonly value: number;
	readonly min: number;
	readonly max: number;
	readonly step?: number;
	readonly unit?: string;
	readonly emphasis?: "hero" | "row" | "nested";
	readonly intent?: "primary" | "success" | "warning" | "error" | "info";
}

export interface SegmentedControlModel extends ControlBase {
	readonly kind: "segmented";
	readonly emphasis?: "prominent" | "row";
	readonly value: string;
	readonly options: readonly MenuOption[];
}

export interface ToggleControl extends ControlBase {
	readonly kind: "toggle";
	readonly value: boolean;
	readonly keybind?: Enum.KeyCode | Enum.UserInputType;
}

export interface KeybindControl extends ControlBase {
	readonly kind: "keybind";
	readonly value: Enum.KeyCode | Enum.UserInputType;
	readonly readOnly?: boolean;
}

export interface ActionControl extends ControlBase {
	readonly kind: "action";
	readonly action: string;
	readonly confirm?: string;
	readonly variant?: "primary" | "secondary" | "danger";
}

export interface ModelViewerControl extends ControlBase {
	readonly kind: "model-viewer";
	readonly key?: string;
	readonly resolve?: () => Model | undefined;
	readonly height?: number;
}

export type MenuControl =
	| SliderControl
	| SegmentedControlModel
	| ToggleControl
	| KeybindControl
	| ActionControl
	| ModelViewerControl;

export interface MenuSection {
	readonly id: string;
	readonly label: string;
	readonly treatment?: "card" | "list" | "plain" | "grid" | "style";
	readonly controls: readonly MenuControl[];
}

export interface CharacterPreviewObservation {
	readonly bounds: { readonly position: Vector2; readonly size: Vector2 };
	readonly bodyParts: readonly {
		readonly visible: true;
		readonly corners: readonly Vector2[];
	}[];
}

export interface CharacterPreviewPaletteTarget {
	readonly id: "outline" | "fill" | "name" | "weapon" | "healthLow" | "healthHigh";
	readonly label: string;
	readonly color: Color3;
	readonly alpha?: number;
	readonly defaultColor: Color3;
	readonly defaultAlpha?: number;
}

export interface CharacterPreviewPaletteRelationship {
	readonly id: "enemy" | "teammate";
	readonly label: "Enemies" | "Teammates";
	readonly fillAlpha: number;
	readonly targets: readonly CharacterPreviewPaletteTarget[];
}

export interface CharacterPreviewPalette {
	readonly checkerboardImage?: string;
	readonly relationships: readonly CharacterPreviewPaletteRelationship[];
}

export interface CharacterPreviewModel {
	readonly kind: "character";
	readonly key?: string;
	readonly resolve?: () => Model | undefined;
	readonly publish?: (observation?: CharacterPreviewObservation) => void;
	readonly report?: (stage: string, detail?: string) => void;
	readonly weaponLabel?: string;
	readonly worldRenderer?: "limn" | "native";
	readonly nameLabel?: string;
	readonly boxes?: boolean;
	readonly chams?: boolean;
	readonly names?: boolean;
	readonly health?: boolean;
	readonly weapon?: boolean;
	readonly chamsExcludeAccessories?: boolean;
	readonly chamsPerPart?: boolean;
	readonly chamsColor?: Color3;
	readonly chamsTransparency?: number;
	readonly outlineColor?: Color3;
	readonly palette?: CharacterPreviewPalette;
}

export interface MenuPage {
	readonly id: string;
	readonly label: string;
	readonly icon?: string;
	readonly layout?: "standard" | "toggle-grid";
	readonly views?: readonly { readonly id: "preview" | "colors"; readonly label: string }[];
	readonly preview?: CharacterPreviewModel;
	readonly sections: readonly MenuSection[];
}

export interface WhatsNewFeature {
	readonly tab?: string;
	readonly name: string;
	readonly note?: string;
	readonly text?: string;
}

export interface WhatsNewGroup {
	readonly tab: string;
	readonly items: readonly WhatsNewFeature[];
}

export interface WhatsNewSection {
	readonly id: string;
	readonly label: string;
	readonly items: readonly string[];
	readonly groups?: readonly WhatsNewGroup[];
}

export interface WhatsNewRelease {
	readonly version: string;
	readonly displayVersion?: string;
	readonly channel?: "beta" | "released";
	readonly date: string;
	readonly title: string;
	readonly body: string;
	readonly sections?: readonly WhatsNewSection[];
}

export interface WhatsNewModel {
	readonly visible: boolean;
	readonly current: string;
	readonly previous?: string;
	readonly showingAll: boolean;
	readonly entries: readonly WhatsNewRelease[];
	readonly releases?: readonly WhatsNewRelease[];
	readonly fresh?: { readonly [version: string]: boolean };
}

export interface FooterItem {
	readonly id: string;
	readonly icon?: "signal";
	readonly label: string;
	readonly tone?: "positive" | "warning" | "negative" | "neutral";
	readonly value: string;
}

export interface ActionNotificationModel {
	readonly action: string;
	readonly tone?: "success" | "warning" | "error";
	readonly confirmLabel?: string;
	readonly position?: "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right";
	readonly text: string;
	readonly title: string;
}

export interface FarmMonitorEgg {
	readonly uid: string;
	readonly name: string;
	readonly icon: string;
	readonly rarity: string;
	readonly rarityColor: Color3;
	readonly area: string;
	readonly size: number;
	readonly state: string;
	readonly reason?: string;
	readonly eligible?: boolean;
	readonly target?: boolean;
	readonly secured?: boolean;
}

export interface FloatingMonitorModel {
	readonly visible: boolean;
	readonly stage: string;
	readonly detail: string;
	readonly players: number;
	readonly targets: number;
	readonly eggs: readonly FarmMonitorEgg[];
	readonly securedEggs?: readonly FarmMonitorEgg[];
}

export interface UniversalHubMenuModel {
	readonly brandLabel: string;
	readonly brandIcon?: string;
	readonly gameLabel: string;
	readonly gameIcon?: string;
	readonly footer?: readonly FooterItem[];
	readonly floatingMonitor?: FloatingMonitorModel;
	readonly notification?: ActionNotificationModel;
	readonly enemyAudienceIcon?: string;
	readonly allyAudienceIcon?: string;
	readonly visible: boolean;
	readonly whatsNew?: WhatsNewModel;
	readonly pages: readonly MenuPage[];
	readonly onValueChange: (id: string, value: MenuValue, persist: boolean) => void;
	readonly onAction?: (name: string) => void;
	readonly onDismissNotification?: () => void;
}

export interface UniversalHubMenuHandle {
	readonly update: (model: UniversalHubMenuModel) => void;
	readonly setVisible: (visible: boolean) => void;
	readonly destroy: () => void;
}

export function validateModel(model: UniversalHubMenuModel): void {
	if (model.pages.size() === 0) error("UniversalHubMenu requires at least one page");
	const ids = new Set<string>();
	for (const page of model.pages) {
		if (page.id === "" || ids.has(`page:${page.id}`)) error(`Duplicate or empty page id: ${page.id}`);
		ids.add(`page:${page.id}`);
		for (const section of page.sections) {
			if (section.id === "" || ids.has(`section:${section.id}`)) error(`Duplicate or empty section id: ${section.id}`);
			ids.add(`section:${section.id}`);
			for (const control of section.controls) {
				if (control.id === "" || ids.has(`control:${control.id}`))
					error(`Duplicate or empty control id: ${control.id}`);
				ids.add(`control:${control.id}`);
				if (control.kind === "slider") {
					if (control.max <= control.min) error(`Slider ${control.id} requires max > min`);
					if (control.value < control.min || control.value > control.max)
						error(`Slider ${control.id} value is outside its range`);
				}
				if (control.kind === "segmented") {
					if (control.options.size() < 2) error(`Segmented control ${control.id} requires at least two options`);
					if (control.options.find((option) => option.value === control.value) === undefined)
						error(`Segmented control ${control.id} has an unknown value`);
				}
			}
		}
	}
}
