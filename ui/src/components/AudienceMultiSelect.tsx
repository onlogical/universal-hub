import React from "@rbxts/react";
import { Button } from "@prism/components/Button";
import { Popover } from "@prism/components/Popover";

export interface AudienceMultiSelectOption {
	readonly value: string;
	readonly label: string;
	readonly disabled?: boolean;
}

export interface AudienceMultiSelectProps {
	readonly options: readonly AudienceMultiSelectOption[];
	readonly value: readonly string[];
	readonly onChange: (value: readonly string[]) => void;
	readonly onOpenedChange?: (opened: boolean) => void;
	readonly placeholder?: string;
	readonly width?: number | string | UDim;
	readonly height?: number | string | UDim;
	readonly zIndex?: number;
}

export function AudienceMultiSelect(props: AudienceMultiSelectProps): React.ReactElement {
	const selected = (value: string) => props.value.includes(value);
	const labels = props.options.filter((option) => selected(option.value)).map((option) => option.label);
	const toggle = (option: AudienceMultiSelectOption) => {
		if (option.disabled) return;
		props.onChange(
			selected(option.value)
				? props.value.filter((value) => value !== option.value)
				: [...props.value, option.value],
		);
	};

	return (
		<Popover
			content={
				<frame BackgroundTransparency={1} BorderSizePixel={0} AutomaticSize={Enum.AutomaticSize.Y} Size={UDim2.fromOffset(190, 0)}>
					<uilistlayout Padding={new UDim(0, 4)} SortOrder={Enum.SortOrder.LayoutOrder} />
					{props.options.map((option, index) => {
						const active = selected(option.value);
						return (
							<textbutton
								key={option.value}
								LayoutOrder={index}
								AutoButtonColor={false}
								BackgroundColor3={active ? Color3.fromRGB(91, 39, 30) : Color3.fromRGB(31, 31, 34)}
								BorderSizePixel={0}
								Font={Enum.Font.BuilderSans}
								Size={UDim2.fromOffset(190, 32)}
								Text={`${active ? "✓  " : "    "}${option.label}`}
								TextColor3={option.disabled ? Color3.fromRGB(103, 115, 126) : Color3.fromRGB(244, 247, 249)}
								TextSize={14}
								TextXAlignment={Enum.TextXAlignment.Left}
								Event={{ Activated: () => toggle(option) }}
							>
								<uicorner CornerRadius={new UDim(0, 5)} />
								<uipadding PaddingLeft={new UDim(0, 10)} />
							</textbutton>
						);
					})}
				</frame>
			}
			placement="bottom"
			align="end"
			triggerMode="click"
			closeOnOutsidePress
			onOpenedChange={props.onOpenedChange}
			width={props.width}
			height={props.height}
			zIndex={props.zIndex}
		>
			<Button
				label={labels.size() === 0 ? (props.placeholder ?? "Select") : labels.join(", ")}
				variant="outline"
				color="secondary"
				fullWidth
				width="100%"
			/>
		</Popover>
	);
}
