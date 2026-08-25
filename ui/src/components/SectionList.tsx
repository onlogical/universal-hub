import React from "@rbxts/react";
import { Box } from "@prism/components/Box";
import { Stack } from "@prism/components/Stack";
import { theme } from "@prism/theme";
import type { MenuPage, UniversalHubMenuModel } from "../contracts";
import { ControlView } from "./ControlView";

export function SectionList({
  page,
  model,
}: {
  readonly page: MenuPage;
  readonly model: UniversalHubMenuModel;
}): React.ReactElement {
  return (
    <Box
      width="100%"
      bg={theme.background.surface}
      radius="md"
      p="md"
      stroke={{ color: theme.border.subtle, thickness: 1 }}
    >
      <Stack width="100%" gap="md">
        {page.sections.map((section, sectionIndex) => (
          <React.Fragment key={section.id}>
            <Stack
              width="100%"
              gap="md"
            >
              {section.controls.map((control, controlIndex) => (
                <ControlView
                  key={control.id}
                  control={control}
                  model={model}
                  layoutOrder={controlIndex}
                />
              ))}
            </Stack>
            {sectionIndex < page.sections.size() - 1 && (
              <frame
                BackgroundColor3={Color3.fromRGB(48, 48, 52)}
                BackgroundTransparency={0.25}
                BorderSizePixel={0}
                Size={new UDim2(1, 0, 0, 1)}
              />
            )}
          </React.Fragment>
        ))}
      </Stack>
    </Box>
  );
}
