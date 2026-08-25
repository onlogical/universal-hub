import React from "@rbxts/react";
import type { MenuSection, UniversalHubMenuModel } from "../contracts";
import { EggRadar } from "../games/stealanegg/EggRadar";

type CustomSectionRenderer = (model: UniversalHubMenuModel) => React.ReactElement;

function eggRadarEnabled(model: UniversalHubMenuModel): boolean {
	for (const page of model.pages) {
		for (const section of page.sections) {
			const control = section.controls.find((candidate) => candidate.id === "eggRadar");
			if (control !== undefined) return control.kind === "toggle" && control.value;
		}
	}
	return false;
}

const renderers = new Map<string, CustomSectionRenderer>();
renderers.set("eggRadar", (model) =>
	eggRadarEnabled(model) ? <EggRadar monitor={model.floatingMonitor} /> : <React.Fragment />,
);

export function hasCustomSectionRenderer(section: MenuSection): boolean {
	return renderers.has(section.id);
}

export function CustomSectionView({
	section,
	model,
}: {
	readonly section: MenuSection;
	readonly model: UniversalHubMenuModel;
}): React.ReactElement {
	const render = renderers.get(section.id);
	return render !== undefined ? render(model) : <React.Fragment />;
}
