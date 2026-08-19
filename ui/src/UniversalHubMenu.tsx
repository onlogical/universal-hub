import React from "@rbxts/react";
import { Box } from "@prism/components/Box";
import { ScrollArea } from "@prism/components/ScrollArea";
import { Tabs } from "@prism/components/Tabs";
import { Text } from "@prism/components/Text";
import { ThemeProvider } from "@prism/theme";
import { theme } from "@prism/theme";
import type { UniversalHubMenuModel } from "./contracts";
import { SectionList } from "./components/SectionList";
import { CombatTelemetry } from "./components/CombatTelemetry";
import { WhatsNewModal } from "./components/WhatsNewModal";
import { HUB_THEME } from "./theme";
import { VisualsPage } from "./visuals/VisualsPage";

const UserInputService = game.GetService("UserInputService");

export function UniversalHubMenu({
  model,
}: {
  readonly model: UniversalHubMenuModel;
}): React.ReactElement {
  const shellRef = React.useRef<Frame>();
  const dragRef = React.useRef<{
    readonly kind: "mouse" | "touch";
    readonly touch?: InputObject;
    readonly pointer: Vector2;
    readonly right: number;
    readonly top: number;
  }>();
  const [shellPosition, setShellPosition] = React.useState(
    new UDim2(1, -32, 0, 28),
  );

  React.useEffect(() => {
    const move = UserInputService.InputChanged.Connect((input) => {
      const drag = dragRef.current;
      if (drag === undefined) return;
      if (
        drag.kind === "mouse" &&
        input.UserInputType !== Enum.UserInputType.MouseMovement
      )
        return;
      if (drag.kind === "touch" && input !== drag.touch) return;
      const shell = shellRef.current;
      if (shell === undefined) return;
      const delta = new Vector2(input.Position.X, input.Position.Y).sub(
        drag.pointer,
      );
      const viewport =
        game.GetService("Workspace").CurrentCamera?.ViewportSize ??
        new Vector2(1920, 1080);
      const right = math.clamp(
        drag.right + delta.X,
        shell.AbsoluteSize.X + 8,
        viewport.X - 8,
      );
      const top = math.clamp(
        drag.top + delta.Y,
        8,
        math.max(8, viewport.Y - shell.AbsoluteSize.Y - 8),
      );
      setShellPosition(UDim2.fromOffset(right, top));
    });
    const finish = UserInputService.InputEnded.Connect((input) => {
      const drag = dragRef.current;
      if (
        drag !== undefined &&
        ((drag.kind === "mouse" &&
          input.UserInputType === Enum.UserInputType.MouseButton1) ||
          (drag.kind === "touch" && input === drag.touch))
      )
        dragRef.current = undefined;
    });
    return () => {
      dragRef.current = undefined;
      move.Disconnect();
      finish.Disconnect();
    };
  }, []);

  const beginDrag = React.useCallback((input: InputObject) => {
    const kind =
      input.UserInputType === Enum.UserInputType.MouseButton1
        ? "mouse"
        : input.UserInputType === Enum.UserInputType.Touch
          ? "touch"
          : undefined;
    const shell = shellRef.current;
    if (kind === undefined || shell === undefined) return;
    const [inset] = game.GetService("GuiService").GetGuiInset();
    dragRef.current = {
      kind,
      touch: kind === "touch" ? input : undefined,
      pointer: new Vector2(input.Position.X, input.Position.Y),
      right: shell.AbsolutePosition.X + shell.AbsoluteSize.X + inset.X,
      top: shell.AbsolutePosition.Y + inset.Y,
    };
  }, []);

  const firstPage = model.pages[0];
  const [activePageId, setActivePageId] = React.useState(firstPage.id);
  const activePage =
    model.pages.find((page) => page.id === activePageId) ?? firstPage;
  React.useEffect(() => {
    if (model.pages.find((page) => page.id === activePageId) === undefined)
      setActivePageId(model.pages[0].id);
  }, [model.pages, activePageId]);
  const tabs = model.pages.map((page) => ({
    value: page.id,
    label: page.label,
    icon: page.icon,
  }));

  return (
    <ThemeProvider theme={HUB_THEME}>
      <WhatsNewModal notice={model.whatsNew} onAction={model.onAction} />
      <CombatTelemetry telemetry={model.combatTelemetry} />
      <frame
        key="shell"
        ref={shellRef}
        AnchorPoint={new Vector2(1, 0)}
        Position={shellPosition}
        Size={new UDim2(0, 520, 0, 860)}
        BackgroundColor3={Color3.fromRGB(18, 18, 19)}
        BackgroundTransparency={model.visible ? 0.02 : 1}
        BorderSizePixel={0}
        Visible={model.visible}
        ClipsDescendants={false}
      >
        <uicorner CornerRadius={new UDim(0, 10)} />
        <uistroke
          Color={Color3.fromRGB(68, 68, 73)}
          Transparency={0.2}
          Thickness={1}
        />
        <frame
          key="content"
          Position={UDim2.fromOffset(1, 1)}
          Size={new UDim2(1, -2, 1, -2)}
          BackgroundTransparency={1}
          BorderSizePixel={0}
          ClipsDescendants
        >
          <uicorner CornerRadius={new UDim(0, 9)} />
          <frame
            key="header"
            Active
            BackgroundColor3={Color3.fromRGB(24, 24, 26)}
            BorderSizePixel={0}
            Size={new UDim2(1, 0, 0, 58)}
            Event={{ InputBegan: (_frame, input) => beginDrag(input) }}
          >
            {model.brandIcon !== undefined && (
              <imagelabel
                BackgroundTransparency={1}
                BorderSizePixel={0}
                Image={model.brandIcon}
                Position={UDim2.fromOffset(18, 15)}
                Size={UDim2.fromOffset(28, 28)}
                ScaleType={Enum.ScaleType.Fit}
              />
            )}
            <Text
              text={model.brandLabel}
              size="lg"
              weight={800}
              color={theme.text.primary}
              position={UDim2.fromOffset(54, 17)}
              width={210}
              height={24}
              slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
            />
            <Text
              text={model.gameLabel}
              size="lg"
              weight={800}
              color={theme.text.primary}
              position={new UDim2(1, -248, 0, 17)}
              width={194}
              height={24}
              slotProps={{
                root: { TextXAlignment: Enum.TextXAlignment.Right },
              }}
            />
            {model.gameIcon !== undefined && (
              <imagelabel
                BackgroundColor3={Color3.fromRGB(31, 31, 34)}
                BorderSizePixel={0}
                Image={model.gameIcon}
                Position={new UDim2(1, -46, 0, 15)}
                Size={UDim2.fromOffset(28, 28)}
                ScaleType={Enum.ScaleType.Crop}
              >
                <uicorner CornerRadius={new UDim(0, 6)} />
              </imagelabel>
            )}
            <textbutton
              Active
              AutoButtonColor={false}
              BackgroundTransparency={1}
              BorderSizePixel={0}
              Size={UDim2.fromScale(1, 1)}
              Text=""
              ZIndex={20}
              Event={{ InputBegan: (_button, input) => beginDrag(input) }}
            />
          </frame>
          <frame
            BackgroundColor3={Color3.fromRGB(24, 24, 26)}
            BorderSizePixel={0}
            Position={UDim2.fromOffset(12, 64)}
            Size={new UDim2(1, -24, 0, 38)}
            ClipsDescendants
            ZIndex={4}
          >
            <uicorner CornerRadius={new UDim(0, 8)} />
            <uistroke
              Color={Color3.fromRGB(68, 68, 73)}
              Transparency={0.18}
              Thickness={1}
            />
            <Tabs
              tabs={tabs}
              value={activePage.id}
              onChange={setActivePageId}
              variant="line"
              color="primary"
              size="md"
              styleOverrides={{
                list: (_styles, context) => ({
                  strokeColor: context.theme.colors.border.subtle,
                  strokeTransparency: 1,
                }),
                tab: (_styles, context) => ({
                  backgroundColor:
                    context.state === "selected"
                      ? context.theme.colors.action.pressed
                      : context.theme.colors.action.hover,
                  backgroundTransparency:
                    context.state === "selected"
                      ? 0.76
                      : context.state === "hovered" ||
                          context.state === "focused"
                        ? 0.62
                        : 1,
                  strokeTransparency: 1,
                  textColor:
                    context.state === "selected"
                      ? context.theme.colors.primary.main
                      : context.theme.colors.text.secondary,
                  indicatorTransparency: 1,
                }),
              }}
              fullWidth
              width={new UDim(1, 30)}
              height={38}
              position={UDim2.fromOffset(-15, 0)}
              slotProps={{
                root: { ZIndex: 5 },
                list: { BackgroundTransparency: 1 },
                listLayout: { Padding: new UDim(0, 0) },
                tabCorner: { CornerRadius: new UDim(0, 0) },
                tabIcon: {
                  AnchorPoint: new Vector2(0.5, 0.5),
                  Position: new UDim2(0.5, -34, 0.5, 0),
                },
                tabIndicator: { Visible: false },
                tabText: {
                  Position: new UDim2(0.5, -20, 0, 0),
                  Size: new UDim2(0.5, 20, 1, 0),
                  TextXAlignment: Enum.TextXAlignment.Left,
                },
                panel: { Visible: false },
              }}
            />
          </frame>
          <ScrollArea
            width="100%"
            height={new UDim(1, -110)}
            position={UDim2.fromOffset(0, 110)}
            direction="vertical"
            scrollbarSize={3}
          >
            <Box width="100%" p="xl">
              {activePage.layout === "toggle-grid" ? (
                <VisualsPage page={activePage} model={model} />
              ) : (
                <SectionList page={activePage} model={model} />
              )}
            </Box>
          </ScrollArea>
        </frame>
      </frame>
    </ThemeProvider>
  );
}
