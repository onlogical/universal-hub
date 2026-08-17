import type { ThemeOverride } from "@prism/theme";

const shell = Color3.fromRGB(18, 18, 19);
const surface = Color3.fromRGB(24, 24, 26);
const raised = Color3.fromRGB(31, 31, 34);
const overlay = Color3.fromRGB(38, 38, 42);
const divider = Color3.fromRGB(48, 48, 52);

export const HUB_THEME: ThemeOverride = {
	colors: {
		primary: {
			main: Color3.fromRGB(255, 118, 87),
			light: Color3.fromRGB(255, 167, 145),
			dark: Color3.fromRGB(91, 39, 30),
			contrast: Color3.fromRGB(28, 11, 8),
		},
		secondary: {
			main: Color3.fromRGB(101, 157, 214),
			light: Color3.fromRGB(157, 199, 235),
			dark: Color3.fromRGB(71, 121, 174),
			contrast: Color3.fromRGB(9, 20, 31),
		},
		info: {
			main: Color3.fromRGB(101, 157, 214),
			light: Color3.fromRGB(157, 199, 235),
			dark: Color3.fromRGB(71, 121, 174),
			contrast: Color3.fromRGB(9, 20, 31),
		},
		warning: {
			main: Color3.fromRGB(255, 190, 92),
			light: Color3.fromRGB(255, 217, 151),
			dark: Color3.fromRGB(210, 137, 47),
			contrast: Color3.fromRGB(28, 18, 7),
		},
		error: {
			main: Color3.fromRGB(255, 111, 133),
			light: Color3.fromRGB(255, 163, 176),
			dark: Color3.fromRGB(204, 67, 89),
			contrast: Color3.fromRGB(31, 9, 13),
		},
		success: {
			main: Color3.fromRGB(98, 214, 173),
			light: Color3.fromRGB(157, 232, 207),
			dark: Color3.fromRGB(62, 167, 131),
			contrast: Color3.fromRGB(8, 28, 21),
		},
		text: {
			primary: Color3.fromRGB(244, 247, 249),
			secondary: Color3.fromRGB(177, 188, 199),
			disabled: Color3.fromRGB(103, 115, 126),
			inverse: Color3.fromRGB(8, 14, 17),
		},
		background: { default: shell, surface },
		border: {
			subtle: divider,
			default: Color3.fromRGB(68, 68, 73),
			strong: Color3.fromRGB(101, 101, 108),
		},
		action: {
			hover: Color3.fromRGB(43, 43, 47),
			pressed: Color3.fromRGB(52, 52, 57),
			disabled: Color3.fromRGB(105, 105, 111),
			disabledBackground: Color3.fromRGB(31, 31, 34),
		},
	},
	spacing: { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 },
	radius: { xs: 3, sm: 5, md: 8, lg: 10, xl: 12 },
	fontSizes: { xs: 12, sm: 14, md: 16, lg: 18, xl: 22 },
	lineHeights: { xs: 1.2, sm: 1.3, md: 1.35, lg: 1.35, xl: 1.25 },
	fontFamily: Enum.Font.BuilderSans,
};
