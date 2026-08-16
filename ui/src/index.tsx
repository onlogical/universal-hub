import React from "@rbxts/react";
import ReactRoblox from "@rbxts/react-roblox";
import type { UniversalHubMenuHandle, UniversalHubMenuModel } from "./contracts";
import { validateModel } from "./contracts";
import { UniversalHubMenu } from "./UniversalHubMenu";

export function mountUniversalHubMenu(parent: Instance, initialModel: UniversalHubMenuModel): UniversalHubMenuHandle {
	validateModel(initialModel);
	const root = ReactRoblox.createLegacyRoot(parent);
	let destroyed = false;
	let model = initialModel;
	const render = () => root.render(<UniversalHubMenu model={model} />);
	render();
	return {
		update: (nextModel) => {
			if (destroyed) error("UniversalHubMenu cannot update after destroy");
			validateModel(nextModel);
			model = nextModel;
			render();
		},
		setVisible: (visible) => {
			if (destroyed) error("UniversalHubMenu cannot change visibility after destroy");
			model = { ...model, visible };
			render();
		},
		destroy: () => {
			if (destroyed) return;
			destroyed = true;
			root.unmount();
		},
	};
}

export type { UniversalHubMenuHandle, UniversalHubMenuModel } from "./contracts";
