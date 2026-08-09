import React from "@rbxts/react";
import {
	Box,
	ColorPicker,
	MultiSelect,
	Popover,
	ScrollArea,
	Select,
	Stack,
	Switch,
	Tabs,
	Text,
	ThemeProvider,
	colorToHex,
} from "@prism";
import { theme } from "@prism/theme";
import type {
	CharacterPreviewPaletteRelationship,
	CharacterPreviewPaletteTarget,
	MenuControl,
	MenuPage,
	ModelViewerControl,
	ToggleControl,
	UniversalHubMenuModel,
} from "./contracts";
import { ControlView } from "./components/ControlView";
import { HUB_THEME } from "./theme";

const UserInputService = game.GetService("UserInputService");

const PART_CORNERS = [
	new Vector3(-1, -1, -1),
	new Vector3(1, -1, -1),
	new Vector3(1, 1, -1),
	new Vector3(-1, 1, -1),
	new Vector3(-1, -1, 1),
	new Vector3(1, -1, 1),
	new Vector3(1, 1, 1),
	new Vector3(-1, 1, 1),
];

function projectPreviewPoint(camera: Camera, viewport: ViewportFrame, worldPoint: Vector3): Vector2 | undefined {
	const localPoint = camera.CFrame.PointToObjectSpace(worldPoint);
	const depth = -localPoint.Z;
	if (depth <= 0.01) return undefined;
	const size = viewport.AbsoluteSize;
	const focalLength = size.Y / (2 * math.tan(math.rad(camera.FieldOfView) * 0.5));
	const [guiInset] = game.GetService("GuiService").GetGuiInset();
	const viewportPosition = viewport.AbsolutePosition.add(guiInset);
	const point = viewportPosition.add(
		new Vector2(
			size.X * 0.5 + (localPoint.X * focalLength) / depth,
			size.Y * 0.5 - (localPoint.Y * focalLength) / depth,
		),
	);
	return point;
}

function pageControls(page: MenuPage): MenuControl[] {
	const controls = new Array<MenuControl>();
	for (const section of page.sections) for (const control of section.controls) controls.push(control);
	return controls;
}

function ViewportDummy({
	preview,
	suspended = false,
}: {
	readonly preview?: MenuPage["preview"];
	readonly suspended?: boolean;
}): React.ReactElement {
	const [viewport, setViewport] = React.useState<ViewportFrame>();
	const [resolvedSubject, setResolvedSubject] = React.useState<Model>();
	const [scene, setScene] = React.useState<{
		readonly dummy: Model;
		readonly camera: Camera;
		readonly world: WorldModel;
	}>();
	const previewRef = React.useRef(preview);
	const yawRef = React.useRef(math.pi);
	const hoveredRef = React.useRef(false);
	const previousMouseIconRef = React.useRef<string>();
	const rotationGestureRef = React.useRef<{
		readonly input: InputObject;
		pointer: Vector2;
		changed?: RBXScriptConnection;
		ended?: RBXScriptConnection;
	}>();
	previewRef.current = preview;

	const showRotationCursor = React.useCallback((dragging: boolean) => {
		const mouse = game.GetService("Players").LocalPlayer.GetMouse();
		if (previousMouseIconRef.current === undefined) previousMouseIconRef.current = mouse.Icon;
		mouse.Icon = dragging ? "rbxasset://SystemCursors/ClosedHand" : "rbxasset://SystemCursors/OpenHand";
	}, []);

	const restoreCursor = React.useCallback(() => {
		const previous = previousMouseIconRef.current;
		if (previous === undefined) return;
		game.GetService("Players").LocalPlayer.GetMouse().Icon = previous;
		previousMouseIconRef.current = undefined;
	}, []);

	const stopRotation = React.useCallback(() => {
		const gesture = rotationGestureRef.current;
		rotationGestureRef.current = undefined;
		gesture?.changed?.Disconnect();
		gesture?.ended?.Disconnect();
		if (hoveredRef.current) showRotationCursor(false);
		else restoreCursor();
	}, [restoreCursor, showRotationCursor]);

	React.useEffect(
		() => () => {
			stopRotation();
			restoreCursor();
		},
		[restoreCursor, stopRotation],
	);

	React.useEffect(() => {
		// A new preview owns a fresh orientation and must not inherit an active gesture.
		stopRotation();
		yawRef.current = math.pi;
		let cancelled = false;
		setResolvedSubject(undefined);
		if (preview?.resolve === undefined) return;
		preview.report?.("resolving");
		task.spawn(() => {
			const [resolved, result] = pcall(() => preview.resolve!());
			if (!resolved || result === undefined || !result.IsA("Model")) {
				preview.report?.("resolve-failed", tostring(result));
				return;
			}
			if (cancelled) result.Destroy();
			else {
				preview.report?.("resolved");
				setResolvedSubject(result);
			}
		});
		return () => {
			cancelled = true;
		};
	}, [preview?.key, stopRotation]);

	// Resolve and mount the avatar independently from renderer settings. Toggling ESP
	// options must not recreate a potentially expensive resolved preview model.
	React.useEffect(() => {
		if (viewport === undefined) return;
		if (preview?.resolve !== undefined && resolvedSubject === undefined) return;
		let cancelled = false;
		const players = game.GetService("Players");
		const world = new Instance("WorldModel");
		world.Name = "LimnPreviewWorld";
		world.Parent = viewport;
		const camera = new Instance("Camera");
		camera.FieldOfView = 28;
		camera.Parent = viewport;
		viewport.CurrentCamera = camera;
		task.spawn(() => {
			let dummy = resolvedSubject;
			const sourceCharacter = players.LocalPlayer.Character;
			if (dummy === undefined) {
				if (cancelled) return;
				let sourceHumanoid = sourceCharacter?.FindFirstChildOfClass("Humanoid");
				if (sourceHumanoid === undefined && sourceCharacter !== undefined) {
					const found = sourceCharacter.WaitForChild("Humanoid", 10);
					if (found?.IsA("Humanoid")) sourceHumanoid = found;
				}
				const rigType = sourceHumanoid?.RigType ?? Enum.HumanoidRigType.R15;
				const [applied, appliedDescription] =
					sourceHumanoid === undefined
						? [false, "missing humanoid"]
						: pcall(() => sourceHumanoid.GetAppliedDescription());
				let description: HumanoidDescription;
				if (applied && typeIs(appliedDescription, "Instance") && appliedDescription.IsA("HumanoidDescription"))
					description = appliedDescription;
				else description = players.GetHumanoidDescriptionFromUserIdAsync(players.LocalPlayer.UserId);
				for (let attempt = 1; attempt <= 3 && dummy === undefined && !cancelled; attempt += 1) {
					const [succeeded, result] = pcall(() =>
						players.CreateHumanoidModelFromDescriptionAsync(description, rigType),
					);
					if (succeeded) dummy = result;
					else if (attempt < 3) task.wait(attempt * 0.4);
				}
				description.Destroy();
			}
			if (dummy === undefined) return;
			if (cancelled) {
				dummy.Destroy();
				return;
			}
			dummy.Name = "LimnPreviewAvatar";
			for (const descendant of dummy.GetDescendants()) {
				if (descendant.IsA("BasePart")) {
					descendant.CanCollide = false;
					descendant.CanQuery = false;
					descendant.CanTouch = false;
				} else if (descendant.IsA("Script") || descendant.IsA("LocalScript")) descendant.Destroy();
			}
			previewRef.current?.report?.("sanitized");
			const root = dummy.FindFirstChild("HumanoidRootPart");
			if (root?.IsA("BasePart")) root.Anchored = true;
			previewRef.current?.report?.("anchored");
			yawRef.current = math.pi;
			dummy.PivotTo(CFrame.Angles(0, yawRef.current, 0));
			previewRef.current?.report?.("pivoted");
			dummy.Parent = world;
			previewRef.current?.report?.("mounted");
			const humanoid = dummy.FindFirstChildOfClass("Humanoid");
			const animator = humanoid?.FindFirstChildOfClass("Animator");
			if (animator !== undefined && dummy.GetAttribute("UniversalHubPreviewStatic") !== true) {
				const animation = new Instance("Animation");
				const previewIdle = dummy.FindFirstChild("UniversalHubPreviewIdle", true);
				const configuredIdle = sourceCharacter
					?.FindFirstChild("Animate")
					?.FindFirstChild("idle")
					?.FindFirstChild("Animation1");
				animation.AnimationId = previewIdle?.IsA("Animation")
					? previewIdle.AnimationId
					: configuredIdle?.IsA("Animation")
						? configuredIdle.AnimationId
						: "rbxassetid://507766388";
				const [loaded, track] = pcall(() => animator.LoadAnimation(animation));
				if (loaded) {
					track.Looped = true;
					track.Play(0.15, 1, 1);
				}
				animation.Destroy();
			}
			if (cancelled) return;
			const [bounds, size] = dummy.GetBoundingBox();
			const focus = bounds.Position;
			const distance = math.max(size.Y * 2.35, 7);
			camera.CFrame = CFrame.lookAt(focus.add(new Vector3(0, 0, distance)), focus);
			previewRef.current?.report?.("ready");
			setScene({ dummy, camera, world });
		});
		return () => {
			cancelled = true;
			stopRotation();
			setScene(undefined);
			camera.Destroy();
			world.Destroy();
		};
	}, [viewport, preview?.key, resolvedSubject, stopRotation]);

	// ViewportFrames do not composite Roblox Highlights. Native Chams therefore
	// restyle the single owned preview rig and restore it deterministically.
	React.useEffect(() => {
		if (scene === undefined || preview?.worldRenderer !== "native" || preview.chams !== true) return;
		const restore = new Array<() => void>();
		const textureStash = new Instance("Folder");
		textureStash.Name = "UniversalHubPreviewTextureStash";
		textureStash.Parent = scene.world;
		const chamsColor = preview.chamsColor ?? Color3.fromRGB(255, 118, 87);
		for (const descendant of scene.dummy.GetDescendants()) {
			if (descendant.IsA("Shirt")) {
				const value = descendant.ShirtTemplate;
				descendant.ShirtTemplate = "";
				restore.push(() => {
					if (descendant.Parent !== undefined) descendant.ShirtTemplate = value;
				});
			} else if (descendant.IsA("Pants")) {
				const value = descendant.PantsTemplate;
				descendant.PantsTemplate = "";
				restore.push(() => {
					if (descendant.Parent !== undefined) descendant.PantsTemplate = value;
				});
			} else if (descendant.IsA("ShirtGraphic")) {
				const value = descendant.Graphic;
				descendant.Graphic = "";
				restore.push(() => {
					if (descendant.Parent !== undefined) descendant.Graphic = value;
				});
			}
			if (!descendant.IsA("BasePart") || descendant.Transparency >= 1 || descendant.Name === "HumanoidRootPart")
				continue;
			let accessoryOwned = false;
			let ancestor = descendant.Parent;
			while (ancestor !== undefined && ancestor !== scene.dummy) {
				if (ancestor.IsA("Accessory")) {
					accessoryOwned = true;
					break;
				}
				ancestor = ancestor.Parent;
			}
			if (accessoryOwned && preview.chamsExcludeAccessories === true) continue;
			const material = descendant.Material;
			const color = descendant.Color;
			const transparency = descendant.Transparency;
			const castShadow = descendant.CastShadow;
			descendant.Material = Enum.Material.Neon;
			descendant.Color = chamsColor;
			descendant.Transparency = preview.chamsTransparency ?? 0.42;
			descendant.CastShadow = false;
			restore.push(() => {
				if (descendant.Parent === undefined) return;
				descendant.Material = material;
				descendant.Color = color;
				descendant.Transparency = transparency;
				descendant.CastShadow = castShadow;
			});
			if (descendant.IsA("MeshPart")) {
				const textureId = descendant.TextureID;
				descendant.TextureID = "";
				restore.push(() => {
					if (descendant.Parent !== undefined) descendant.TextureID = textureId;
				});
			}
			for (const surface of descendant.GetDescendants()) {
				if (surface.IsA("SpecialMesh")) {
					const textureId = surface.TextureId;
					surface.TextureId = "";
					restore.push(() => {
						if (surface.Parent !== undefined) surface.TextureId = textureId;
					});
				} else if (surface.IsA("Decal") || surface.IsA("Texture")) {
					const surfaceTransparency = surface.Transparency;
					surface.Transparency = 1;
					restore.push(() => {
						if (surface.Parent !== undefined) surface.Transparency = surfaceTransparency;
					});
				} else if (surface.IsA("SurfaceAppearance")) {
					const parent = surface.Parent;
					surface.Parent = textureStash;
					restore.push(() => {
						if (parent !== undefined) surface.Parent = parent;
					});
				}
			}
		}
		return () => {
			for (let index = restore.size() - 1; index >= 0; index -= 1) restore[index]();
			textureStash.Destroy();
		};
	}, [
		scene,
		preview?.worldRenderer,
		preview?.chams,
		preview?.chamsExcludeAccessories,
		preview?.chamsColor,
		preview?.chamsTransparency,
	]);

	// Projected geometry supplies renderer-aware labels and outline policy.
	React.useEffect(() => {
		if (viewport === undefined || scene === undefined) return;
		const enabled =
			!suspended &&
			(preview?.boxes === true ||
				preview?.chams === true ||
				preview?.names === true ||
				preview?.health === true ||
				preview?.weapon === true);
		if (!enabled) {
			previewRef.current?.publish?.(undefined);
			return;
		}
		const projectionConnection = game.GetService("RunService").RenderStepped.Connect(() => {
			const currentPreview = previewRef.current;
			if (currentPreview?.publish === undefined) return;
			const bodyParts = new Array<{
				visible: true;
				corners: Vector2[];
				accessory?: true;
			}>();
			let minimum = new Vector2(math.huge, math.huge);
			let maximum = new Vector2(-math.huge, -math.huge);
			for (const descendant of scene.dummy.GetDescendants()) {
				if (!descendant.IsA("BasePart") || descendant.Transparency >= 1) continue;
				let accessoryOwned = false;
				let ancestor = descendant.Parent;
				while (ancestor !== undefined && ancestor !== scene.dummy) {
					if (ancestor.IsA("Accessory")) {
						accessoryOwned = true;
						break;
					}
					ancestor = ancestor.Parent;
				}
				const nativeAccessory = currentPreview?.worldRenderer === "native" && accessoryOwned;
				if (descendant.Name === "HumanoidRootPart" || (accessoryOwned && !nativeAccessory)) continue;
				const corners = new Array<Vector2>();
				const halfSize = descendant.Size.mul(0.5);
				for (const sign of PART_CORNERS) {
					const worldPoint = descendant.CFrame.PointToWorldSpace(
						new Vector3(halfSize.X * sign.X, halfSize.Y * sign.Y, halfSize.Z * sign.Z),
					);
					const point = projectPreviewPoint(scene.camera, viewport, worldPoint);
					if (point === undefined) {
						corners.clear();
						break;
					}
					corners.push(point);
					minimum = new Vector2(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y));
					maximum = new Vector2(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y));
				}
				if (corners.size() === PART_CORNERS.size())
					bodyParts.push({
						visible: true,
						corners,
						accessory: accessoryOwned ? true : undefined,
					});
			}
			if (bodyParts.size() > 0)
				currentPreview.publish({
					bounds: { position: minimum, size: maximum.sub(minimum) },
					bodyParts,
				});
		});
		return () => {
			projectionConnection.Disconnect();
			previewRef.current?.publish?.(undefined);
		};
	}, [viewport, scene, suspended, preview?.boxes, preview?.chams, preview?.health, preview?.names, preview?.weapon]);

	const beginRotation = React.useCallback(
		(input: InputObject) => {
			if (scene === undefined) return;
			const inputType = input.UserInputType;
			if (inputType !== Enum.UserInputType.MouseButton1 && inputType !== Enum.UserInputType.Touch) return;
			stopRotation();
			const gesture = {
				input,
				pointer: new Vector2(input.Position.X, input.Position.Y),
				changed: undefined as RBXScriptConnection | undefined,
				ended: undefined as RBXScriptConnection | undefined,
			};
			rotationGestureRef.current = gesture;
			showRotationCursor(true);
			gesture.changed = UserInputService.InputChanged.Connect((changedInput) => {
				if (rotationGestureRef.current !== gesture) return;
				if (inputType === Enum.UserInputType.Touch) {
					if (changedInput !== input) return;
				} else if (changedInput.UserInputType !== Enum.UserInputType.MouseMovement) return;
				const pointer = new Vector2(changedInput.Position.X, changedInput.Position.Y);
				const horizontalDelta = pointer.X - gesture.pointer.X;
				gesture.pointer = pointer;
				if (horizontalDelta === 0 || scene.dummy.Parent === undefined) return;
				yawRef.current += horizontalDelta * 0.012;
				scene.dummy.PivotTo(CFrame.Angles(0, yawRef.current, 0));
			});
			gesture.ended = UserInputService.InputEnded.Connect((endedInput) => {
				if (rotationGestureRef.current !== gesture) return;
				if (
					inputType === Enum.UserInputType.Touch
						? endedInput === input
						: endedInput.UserInputType === Enum.UserInputType.MouseButton1
				)
					stopRotation();
			});
		},
		[scene, showRotationCursor, stopRotation],
	);

	return (
		<React.Fragment>
			<viewportframe
				key="LimnPreviewViewport"
				ref={setViewport}
				Ambient={Color3.fromRGB(175, 165, 160)}
				LightColor={Color3.fromRGB(255, 205, 190)}
				LightDirection={new Vector3(-1, -1, -1)}
				BackgroundTransparency={1}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(0, 0)}
				Size={UDim2.fromScale(1, 1)}
			/>
			<textbutton
				key="RotationGesture"
				Active
				AutoButtonColor={false}
				BackgroundTransparency={1}
				BorderSizePixel={0}
				Size={UDim2.fromScale(1, 1)}
				Text=""
				ZIndex={5}
				Event={{
					InputBegan: (_button, input) => beginRotation(input),
					MouseEnter: () => {
						hoveredRef.current = true;
						showRotationCursor(rotationGestureRef.current !== undefined);
					},
					MouseLeave: () => {
						hoveredRef.current = false;
						if (rotationGestureRef.current === undefined) restoreCursor();
					},
				}}
			>
				<textlabel
					AnchorPoint={new Vector2(1, 1)}
					BackgroundColor3={Color3.fromRGB(18, 18, 19)}
					BackgroundTransparency={0.24}
					BorderSizePixel={0}
					Font={Enum.Font.GothamMedium}
					Position={new UDim2(1, -9, 1, -8)}
					Size={UDim2.fromOffset(118, 22)}
					Text="Drag to rotate"
					TextColor3={Color3.fromRGB(177, 188, 199)}
					TextSize={11}
					ZIndex={6}
				>
					<uicorner CornerRadius={new UDim(0, 5)} />
				</textlabel>
			</textbutton>
		</React.Fragment>
	);
}
function InteractiveModelViewer({ control }: { readonly control: ModelViewerControl }): React.ReactElement {
	const [viewport, setViewport] = React.useState<ViewportFrame>();
	const [resolvedModel, setResolvedModel] = React.useState<Model>();
	const cameraRef = React.useRef<Camera>();
	const focusRef = React.useRef(Vector3.zero);
	const distanceRef = React.useRef(6);
	const limitsRef = React.useRef({ minimum: 1.5, maximum: 20 });
	const yawRef = React.useRef(0);
	const pitchRef = React.useRef(0);
	const panRef = React.useRef(Vector2.zero);
	const hoveredRef = React.useRef(false);
	const dragRef = React.useRef<{
		readonly kind: "orbit" | "pan";
		readonly input: InputObject;
		pointer: Vector2;
	}>();

	const applyCamera = React.useCallback(() => {
		const camera = cameraRef.current;
		if (camera === undefined) return;
		const pan = panRef.current;
		const target = focusRef.current.add(new Vector3(pan.X, pan.Y, 0));
		const rotation = CFrame.Angles(pitchRef.current, yawRef.current, 0);
		const offset = rotation.VectorToWorldSpace(new Vector3(0, 0, distanceRef.current));
		camera.CFrame = CFrame.lookAt(target.add(offset), target);
	}, []);

	const zoom = React.useCallback(
		(factor: number) => {
			const limits = limitsRef.current;
			distanceRef.current = math.clamp(distanceRef.current * factor, limits.minimum, limits.maximum);
			applyCamera();
		},
		[applyCamera],
	);

	React.useEffect(() => {
		let cancelled = false;
		setResolvedModel(undefined);
		if (control.resolve === undefined) return;
		task.spawn(() => {
			const [succeeded, result] = pcall(() => control.resolve!());
			if (!succeeded || result === undefined || !result.IsA("Model")) return;
			if (cancelled) result.Destroy();
			else setResolvedModel(result);
		});
		return () => {
			cancelled = true;
		};
	}, [control.key]);

	React.useEffect(() => {
		if (viewport === undefined || resolvedModel === undefined) return;
		const world = new Instance("WorldModel");
		world.Parent = viewport;
		const camera = new Instance("Camera");
		camera.FieldOfView = 34;
		camera.Parent = viewport;
		viewport.CurrentCamera = camera;
		cameraRef.current = camera;
		for (const descendant of resolvedModel.GetDescendants()) {
			if (descendant.IsA("BasePart")) {
				descendant.Anchored = true;
				descendant.CanCollide = false;
				descendant.CanQuery = false;
				descendant.CanTouch = false;
			} else if (descendant.IsA("Script") || descendant.IsA("LocalScript")) descendant.Destroy();
		}
		resolvedModel.Parent = world;
		const [bounds, size] = resolvedModel.GetBoundingBox();
		focusRef.current = bounds.Position;
		const largest = math.max(size.X, size.Y, size.Z, 1);
		limitsRef.current = { minimum: largest * 0.65, maximum: largest * 5.5 };
		distanceRef.current = largest * 2.15;
		yawRef.current = math.rad(18);
		pitchRef.current = math.rad(-8);
		panRef.current = Vector2.zero;
		applyCamera();
		return () => {
			dragRef.current = undefined;
			cameraRef.current = undefined;
			camera.Destroy();
			world.Destroy();
		};
	}, [viewport, resolvedModel, applyCamera]);

	React.useEffect(() => {
		const changed = UserInputService.InputChanged.Connect((input) => {
			if (hoveredRef.current && input.UserInputType === Enum.UserInputType.MouseWheel) {
				zoom(input.Position.Z > 0 ? 0.86 : 1.16);
				return;
			}
			const drag = dragRef.current;
			if (drag === undefined || (input !== drag.input && drag.input.UserInputType === Enum.UserInputType.Touch)) return;
			if (
				drag.input.UserInputType !== Enum.UserInputType.Touch &&
				input.UserInputType !== Enum.UserInputType.MouseMovement
			)
				return;
			const pointer = new Vector2(input.Position.X, input.Position.Y);
			const delta = pointer.sub(drag.pointer);
			drag.pointer = pointer;
			if (drag.kind === "orbit") {
				yawRef.current -= delta.X * 0.012;
				pitchRef.current = math.clamp(pitchRef.current - delta.Y * 0.012, math.rad(-80), math.rad(80));
			} else {
				const scale = distanceRef.current * 0.0025;
				panRef.current = panRef.current.add(new Vector2(-delta.X * scale, delta.Y * scale));
			}
			applyCamera();
		});
		const ended = UserInputService.InputEnded.Connect((input) => {
			const drag = dragRef.current;
			if (drag !== undefined && (input === drag.input || input.UserInputType === drag.input.UserInputType))
				dragRef.current = undefined;
		});
		return () => {
			changed.Disconnect();
			ended.Disconnect();
		};
	}, [applyCamera, zoom]);

	const begin = React.useCallback((input: InputObject) => {
		const inputType = input.UserInputType;
		if (
			inputType !== Enum.UserInputType.MouseButton1 &&
			inputType !== Enum.UserInputType.MouseButton2 &&
			inputType !== Enum.UserInputType.Touch
		)
			return;
		dragRef.current = {
			kind:
				inputType === Enum.UserInputType.MouseButton2
					? "pan"
					: UserInputService.IsKeyDown(Enum.KeyCode.LeftShift) || UserInputService.IsKeyDown(Enum.KeyCode.RightShift)
						? "pan"
						: "orbit",
			input,
			pointer: new Vector2(input.Position.X, input.Position.Y),
		};
	}, []);

	return (
		<frame
			BackgroundColor3={Color3.fromRGB(18, 18, 19)}
			BorderSizePixel={0}
			Size={new UDim2(1, 0, 0, control.height ?? 230)}
			ClipsDescendants
		>
			<uicorner CornerRadius={new UDim(0, 7)} />
			<uistroke Color={Color3.fromRGB(48, 48, 52)} Transparency={0.2} Thickness={1} />
			<viewportframe
				ref={setViewport}
				Active
				Ambient={Color3.fromRGB(180, 172, 168)}
				LightColor={Color3.fromRGB(255, 205, 190)}
				LightDirection={new Vector3(-1, -1, -1)}
				BackgroundTransparency={1}
				BorderSizePixel={0}
				Size={UDim2.fromScale(1, 1)}
				Event={{
					InputBegan: (_frame, input) => begin(input),
					MouseEnter: () => {
						hoveredRef.current = true;
					},
					MouseLeave: () => {
						hoveredRef.current = false;
					},
				}}
			/>
			<Text
				text="Drag to orbit  ·  Shift/right-drag to pan  ·  Scroll to zoom"
				size="xs"
				color={theme.text.disabled}
				position={new UDim2(0, 10, 1, -24)}
				width={430}
				height={18}
				slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
			/>
		</frame>
	);
}

function SlidersButton({ open }: { readonly open: boolean }): React.ReactElement {
	const color = open ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(103, 115, 126);
	return (
		<frame
			BackgroundColor3={Color3.fromRGB(31, 31, 34)}
			BorderSizePixel={0}
			Size={UDim2.fromOffset(22, 22)}
			ZIndex={42}
		>
			<uicorner CornerRadius={new UDim(0, 4)} />
			<uistroke
				Color={open ? Color3.fromRGB(255, 118, 87) : Color3.fromRGB(68, 68, 73)}
				Transparency={open ? 0.18 : 0.4}
				Thickness={1}
			/>
			{[6, 11, 16].map((y, index) => (
				<React.Fragment key={tostring(y)}>
					<frame
						BackgroundColor3={color}
						BackgroundTransparency={0.12}
						BorderSizePixel={0}
						Position={UDim2.fromOffset(5, y)}
						Size={UDim2.fromOffset(12, 1)}
						ZIndex={43}
					/>
					<frame
						BackgroundColor3={color}
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
	);
}

function ChamsPopover({
	controls,
	model,
}: {
	readonly controls: readonly MenuControl[];
	readonly model: UniversalHubMenuModel;
}): React.ReactElement {
	return (
		<frame BackgroundTransparency={1} BorderSizePixel={0} Size={UDim2.fromOffset(200, 68)}>
			{controls.map(
				(control, index) =>
					control.kind === "toggle" && (
						<frame
							key={control.id}
							BackgroundTransparency={1}
							BorderSizePixel={0}
							Position={UDim2.fromOffset(0, index * 34)}
							Size={new UDim2(1, 0, 0, 34)}
							ZIndex={51}
						>
							<Text
								text={control.label}
								size="xs"
								weight={500}
								color={theme.text.secondary}
								position={UDim2.fromOffset(0, 0)}
								width={160}
								height={34}
								slotProps={{
									root: {
										TextXAlignment: Enum.TextXAlignment.Left,
										TextYAlignment: Enum.TextYAlignment.Center,
										ZIndex: 52,
									},
								}}
							/>
							<Switch
								checked={control.value}
								onChange={(value) => model.onValueChange(control.id, value, true)}
								color="primary"
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

function VisualToggleTile({
	control,
	model,
	order,
	reserveAction,
	suboptions = [],
}: {
	readonly control: MenuControl;
	readonly model: UniversalHubMenuModel;
	readonly order: number;
	readonly reserveAction: boolean;
	readonly suboptions?: readonly MenuControl[];
}): React.ReactElement {
	const [detailsOpen, setDetailsOpen] = React.useState(false);
	React.useEffect(() => {
		if (suboptions.size() === 0) setDetailsOpen(false);
	}, [suboptions.size()]);
	if (control.kind !== "toggle") return <frame BackgroundTransparency={1} LayoutOrder={order} />;
	const hasDetails = suboptions.size() > 0;
	return (
		<frame
			BackgroundColor3={Color3.fromRGB(31, 31, 34)}
			BorderSizePixel={0}
			LayoutOrder={order}
			ZIndex={detailsOpen ? 40 : 1}
		>
			<uicorner CornerRadius={new UDim(0, 5)} />
			<Text
				text={control.label}
				size="sm"
				weight={600}
				color={theme.text.primary}
				position={UDim2.fromOffset(10, 0)}
				width={reserveAction ? 116 : 142}
				height={40}
				slotProps={{
					root: {
						TextXAlignment: Enum.TextXAlignment.Left,
						TextYAlignment: Enum.TextYAlignment.Center,
					},
				}}
			/>
			{hasDetails && (
				<Popover
					content={<ChamsPopover controls={suboptions} model={model} />}
					placement="bottom"
					align="end"
					triggerMode="click"
					closeOnOutsidePress
					opened={detailsOpen}
					onOpenedChange={setDetailsOpen}
					gap={8}
					styleOverrides={(styles, context) => ({
						...styles,
						shadow: context.theme.shadows.lg,
					})}
					position={new UDim2(1, -10, 0.5, 0)}
					anchor={new Vector2(1, 0.5)}
					width={22}
					height={22}
					zIndex={42}
				>
					<SlidersButton open={detailsOpen} />
				</Popover>
			)}
			<Switch
				checked={control.value}
				onChange={(value) => model.onValueChange(control.id, value, true)}
				color="primary"
				size="md"
				position={new UDim2(1, reserveAction ? -42 : -10, 0.5, 0)}
				anchor={new Vector2(1, 0.5)}
			/>
		</frame>
	);
}

function AudienceMultiSelect({
	controls,
	model,
	onOpenChange,
}: {
	readonly controls: readonly MenuControl[];
	readonly model: UniversalHubMenuModel;
	readonly onOpenChange: (opened: boolean) => void;
}): React.ReactElement {
	const toggleControls = controls.filter((control): control is ToggleControl => control.kind === "toggle");
	const enemyControl = toggleControls.find((control) => control.id === "showEnemies");
	const allyControl = toggleControls.find((control) => control.id === "showTeammates");
	if (enemyControl === undefined || allyControl === undefined)
		return <frame BackgroundTransparency={1} Size={UDim2.fromOffset(0, 0)} />;
	const value = new Array<string>();
	if (enemyControl.value) value.push("enemies");
	if (allyControl.value) value.push("allies");
	return (
		<MultiSelect
			options={[
				{
					value: "enemies",
					label: "Enemies",
					icon: model.enemyAudienceIcon,
					iconColor: Color3.fromRGB(255, 118, 87),
				},
				{
					value: "allies",
					label: "Allies",
					icon: model.allyAudienceIcon,
					iconColor: Color3.fromRGB(101, 157, 214),
				},
			]}
			value={value}
			onChange={(selected) => {
				const enemies = selected.find((entry) => entry === "enemies") !== undefined;
				const allies = selected.find((entry) => entry === "allies") !== undefined;
				if (enemies !== enemyControl.value) model.onValueChange(enemyControl.id, enemies, true);
				if (allies !== allyControl.value) model.onValueChange(allyControl.id, allies, true);
			}}
			onOpenedChange={onOpenChange}
			placeholder="Select visibility"
			maxSelectedLabels={2}
			maxVisibleOptions={2}
			size="md"
			fullWidth
			width={200}
			height={34}
			zIndex={80}
		/>
	);
}

function CompactSegments({
	options,
	value,
	onChange,
}: {
	readonly options: readonly { readonly value: string; readonly label: string }[];
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

function EspTargetColorPicker({
	relationship,
	target,
	model,
	checkerboardImage,
	onOpened,
}: {
	readonly relationship: CharacterPreviewPaletteRelationship;
	readonly target: CharacterPreviewPaletteTarget;
	readonly model: UniversalHubMenuModel;
	readonly checkerboardImage?: string;
	readonly onOpened: () => void;
}): React.ReactElement {
	const fill = target.id === "fill";
	const modelAlpha = fill ? (target.alpha ?? relationship.fillAlpha) : 1;
	const defaultAlpha = fill ? (target.defaultAlpha ?? relationship.fillAlpha) : 1;
	const [draftColor, setDraftColor] = React.useState(target.color);
	const [draftAlpha, setDraftAlpha] = React.useState(modelAlpha);
	React.useEffect(() => setDraftColor(target.color), [target.color]);
	React.useEffect(() => setDraftAlpha(modelAlpha), [modelAlpha]);
	return (
		<ColorPicker
			value={draftColor}
			alpha={draftAlpha}
			alphaEnabled={fill}
			onChange={setDraftColor}
			onChangeEnd={(color) => {
				model.onValueChange(`espColor:${relationship.id}:${target.id}`, colorToHex(color), true);
			}}
			onAlphaChange={(alpha) => {
				if (fill) setDraftAlpha(alpha);
			}}
			onAlphaChangeEnd={(alpha) => {
				if (fill) model.onValueChange(`espAlpha:${relationship.id}`, alpha, true);
			}}
			previousValue={target.defaultColor}
			previousAlpha={defaultAlpha}
			onReset={() => {
				setDraftColor(target.defaultColor);
				setDraftAlpha(defaultAlpha);
				model.onValueChange(`espColor:${relationship.id}:${target.id}`, "", true);
				if (fill) model.onValueChange(`espAlpha:${relationship.id}`, -1, true);
			}}
			checkerboardImage={checkerboardImage}
			placement="left"
			align="center"
			onOpenedChange={(opened) => {
				if (opened) onOpened();
			}}
			width={170}
			height={34}
			position={new UDim2(1, -178, 0, 4)}
			zIndex={100}
			slotProps={{ triggerLabel: { TextSize: 12 }, alphaCheckerboard: { Visible: fill } }}
		/>
	);
}

function EspColorsView({
	page,
	model,
}: {
	readonly page: MenuPage;
	readonly model: UniversalHubMenuModel;
}): React.ReactElement {
	const palette = page.preview?.palette;
	const [relationshipId, setRelationshipId] = React.useState("enemy");
	const [selectedId, setSelectedId] = React.useState("fill");
	if (palette === undefined || palette.relationships.size() === 0)
		return <Text text="ESP colors are unavailable" size="sm" color={theme.text.disabled} />;
	const relationship =
		palette.relationships.find((candidate) => candidate.id === relationshipId) ?? palette.relationships[0];
	return (
		<Box
			width="100%"
			bg={theme.background.surface}
			radius="md"
			p="md"
			stroke={{ color: theme.border.subtle, thickness: 1 }}
		>
			<Stack width="100%" gap="md">
				<CompactSegments
					options={palette.relationships.map((candidate) => ({ value: candidate.id, label: candidate.label }))}
					value={relationship.id}
					onChange={setRelationshipId}
				/>
				<Text
					text={`EDITING ${string.upper(relationship.label)} · ${selectedId === "fill" ? "FILL + ALPHA" : string.upper(selectedId) + " · OPAQUE"}`}
					size="xs"
					weight={800}
					color={theme.text.disabled}
					width="100%"
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				{relationship.targets.map((target) => {
					const selected = target.id === selectedId;
					return (
						<frame
							key={`${relationship.id}:${target.id}`}
							BackgroundColor3={selected ? Color3.fromRGB(38, 38, 42) : Color3.fromRGB(18, 18, 19)}
							BackgroundTransparency={selected ? 0 : 0.25}
							BorderSizePixel={0}
							Size={new UDim2(1, 0, 0, 42)}
						>
							<uicorner CornerRadius={new UDim(0, 6)} />
							<Text
								text={target.label}
								size="sm"
								weight={700}
								color={selected ? Color3.fromRGB(255, 118, 87) : theme.text.primary}
								position={UDim2.fromOffset(12, 0)}
								width={150}
								height={42}
								slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left, ZIndex: 6 } }}
							/>
							<EspTargetColorPicker
								key={`${relationship.id}:${target.id}`}
								relationship={relationship}
								target={target}
								model={model}
								checkerboardImage={palette.checkerboardImage}
								onOpened={() => setSelectedId(target.id)}
							/>
						</frame>
					);
				})}
				<Stack width="100%" direction="horizontal" gap="sm">
					<textbutton
						AutoButtonColor={false}
						BackgroundColor3={Color3.fromRGB(38, 38, 42)}
						BorderSizePixel={0}
						Font={Enum.Font.BuilderSansBold}
						Size={new UDim2(0.5, -4, 0, 34)}
						Text="Reset Relationship"
						TextColor3={Color3.fromRGB(177, 188, 199)}
						TextSize={13}
						Event={{ Activated: () => model.onValueChange(`resetEspRelationship:${relationship.id}`, true, true) }}
					>
						<uicorner CornerRadius={new UDim(0, 6)} />
					</textbutton>
					<textbutton
						AutoButtonColor={false}
						BackgroundColor3={Color3.fromRGB(91, 39, 30)}
						BorderSizePixel={0}
						Font={Enum.Font.BuilderSansBold}
						Size={new UDim2(0.5, -4, 0, 34)}
						Text="Reset All"
						TextColor3={Color3.fromRGB(255, 118, 87)}
						TextSize={13}
						Event={{ Activated: () => model.onValueChange("resetEspAll", true, true) }}
					>
						<uicorner CornerRadius={new UDim(0, 6)} />
					</textbutton>
				</Stack>
			</Stack>
		</Box>
	);
}

function VisualPreview({
	page,
	model,
	styleControl,
	audienceControls,
}: {
	readonly page: MenuPage;
	readonly model: UniversalHubMenuModel;
	readonly styleControl?: MenuControl;
	readonly audienceControls: readonly MenuControl[];
}): React.ReactElement {
	const preview = page.preview;
	const [audienceOpen, setAudienceOpen] = React.useState(false);
	const previewEnabled =
		preview?.boxes === true ||
		preview?.chams === true ||
		preview?.names === true ||
		preview?.health === true ||
		preview?.weapon === true;
	return (
		<frame BackgroundTransparency={1} BorderSizePixel={0} Size={new UDim2(1, 0, 0, 310)}>
			<frame BackgroundTransparency={1} BorderSizePixel={0} Size={new UDim2(1, 0, 0, 34)}>
				<Text
					text="ESP PREVIEW"
					size="xs"
					weight={800}
					color={theme.text.disabled}
					position={UDim2.fromOffset(0, 0)}
					width={110}
					height={34}
					slotProps={{
						root: {
							TextXAlignment: Enum.TextXAlignment.Left,
							TextYAlignment: Enum.TextYAlignment.Center,
						},
					}}
				/>
				{styleControl !== undefined && (
					<frame
						BackgroundTransparency={1}
						BorderSizePixel={0}
						Position={new UDim2(1, -250, 0, 0)}
						Size={UDim2.fromOffset(250, 34)}
					>
						<ControlView control={styleControl} model={model} hideLabel compact />
					</frame>
				)}
			</frame>
			{audienceControls.size() > 0 && (
				<frame
					BackgroundTransparency={1}
					BorderSizePixel={0}
					Position={UDim2.fromOffset(0, 42)}
					Size={new UDim2(1, 0, 0, 34)}
				>
					<Text
						text="VISIBILITY"
						size="xs"
						weight={800}
						color={theme.text.disabled}
						position={UDim2.fromOffset(0, 0)}
						width={110}
						height={34}
						slotProps={{
							root: {
								TextXAlignment: Enum.TextXAlignment.Left,
								TextYAlignment: Enum.TextYAlignment.Center,
							},
						}}
					/>
					<frame
						BackgroundTransparency={1}
						BorderSizePixel={0}
						Position={new UDim2(1, -200, 0, 0)}
						Size={UDim2.fromOffset(200, 34)}
					>
						<AudienceMultiSelect controls={audienceControls} model={model} onOpenChange={setAudienceOpen} />
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
				<uistroke Color={Color3.fromRGB(48, 48, 52)} Transparency={0.3} Thickness={1} />
				{previewEnabled ? (
					<ViewportDummy preview={preview} suspended={audienceOpen} />
				) : (
					<Text
						text="Enable a visual to preview"
						size="sm"
						weight={500}
						color={theme.text.disabled}
						width="100%"
						height={226}
					/>
				)}
			</frame>
		</frame>
	);
}

function SectionView({
	page,
	model,
	visualView = "preview",
}: {
	readonly page: MenuPage;
	readonly model: UniversalHubMenuModel;
	readonly visualView?: "preview" | "colors";
}): React.ReactElement {
	const controls = pageControls(page);
	if (page.layout === "toggle-grid" && visualView === "colors") return <EspColorsView page={page} model={model} />;
	if (page.layout === "toggle-grid") {
		const visualSection = page.sections.find((section) => section.id === "visuals");
		const visualControls =
			visualSection?.controls.filter((control) => control.kind === "toggle" && control.parent === undefined) ?? [];
		const visualSuboptions =
			visualSection?.controls.filter((control) => control.kind === "toggle" && control.parent === "chams") ?? [];
		const audienceControls =
			visualSection?.controls.filter((control) => control.kind === "toggle" && control.parent === "audience") ?? [];
		const styleSection = page.sections.find((section) => section.id === "worldRenderer");
		const extraSections = page.sections.filter((section) => section.id !== "visuals" && section.id !== "worldRenderer");
		const rowCount = math.ceil(visualControls.size() / 2);
		return (
			<Box
				width="100%"
				bg={theme.background.surface}
				radius="md"
				p="md"
				stroke={{ color: theme.border.subtle, thickness: 1 }}
			>
				<Stack width="100%" gap="md">
					<VisualPreview
						page={page}
						model={model}
						styleControl={styleSection?.controls[0]}
						audienceControls={audienceControls}
					/>
					<frame BackgroundTransparency={1} BorderSizePixel={0} Size={new UDim2(1, 0, 0, rowCount * 48)}>
						<uigridlayout
							CellPadding={UDim2.fromOffset(10, 8)}
							CellSize={new UDim2(0.5, -5, 0, 40)}
							FillDirectionMaxCells={2}
							SortOrder={Enum.SortOrder.LayoutOrder}
						/>
						{visualControls.map((control, index) => (
							<VisualToggleTile
								key={control.id}
								control={control}
								model={model}
								order={index}
								reserveAction={page.preview?.worldRenderer === "native" && index % 2 === 1}
								suboptions={control.id === "chams" ? visualSuboptions : []}
							/>
						))}
					</frame>
					{extraSections.map((section) => (
						<Stack key={section.id} width="100%" gap="md">
							<frame
								BackgroundColor3={Color3.fromRGB(48, 48, 52)}
								BackgroundTransparency={0.25}
								BorderSizePixel={0}
								Size={new UDim2(1, 0, 0, 1)}
							/>
							<Text
								text={section.label}
								size="sm"
								weight={800}
								color={theme.text.secondary}
								width="100%"
								slotProps={{
									root: { TextXAlignment: Enum.TextXAlignment.Left },
								}}
							/>
							{section.controls.map((control) =>
								control.kind === "model-viewer" ? (
									<InteractiveModelViewer key={control.id} control={control} />
								) : (
									<ControlView key={control.id} control={control} model={model} />
								),
							)}
						</Stack>
					))}
				</Stack>
			</Box>
		);
	}
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
						<Stack width="100%" gap="md">
							{section.controls.map((control) => (
								<ControlView key={control.id} control={control} model={model} />
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

export function UniversalHubMenu({ model }: { readonly model: UniversalHubMenuModel }): React.ReactElement {
	const shellRef = React.useRef<Frame>();
	const dragRef = React.useRef<{
		readonly kind: "mouse" | "touch";
		readonly touch?: InputObject;
		readonly pointer: Vector2;
		readonly right: number;
		readonly top: number;
	}>();
	const [shellPosition, setShellPosition] = React.useState(new UDim2(1, -32, 0, 28));
	React.useEffect(() => {
		const move = UserInputService.InputChanged.Connect((input) => {
			const drag = dragRef.current;
			if (drag === undefined) return;
			if (drag.kind === "mouse" && input.UserInputType !== Enum.UserInputType.MouseMovement) return;
			if (drag.kind === "touch" && input !== drag.touch) return;
			const shell = shellRef.current;
			if (shell === undefined) return;
			const delta = new Vector2(input.Position.X, input.Position.Y).sub(drag.pointer);
			const viewport = game.GetService("Workspace").CurrentCamera?.ViewportSize ?? new Vector2(1920, 1080);
			const right = math.clamp(drag.right + delta.X, shell.AbsoluteSize.X + 8, viewport.X - 8);
			const top = math.clamp(drag.top + delta.Y, 8, math.max(8, viewport.Y - shell.AbsoluteSize.Y - 8));
			setShellPosition(UDim2.fromOffset(right, top));
		});
		const finish = UserInputService.InputEnded.Connect((input) => {
			const drag = dragRef.current;
			if (drag === undefined) return;
			if (
				(drag.kind === "mouse" && input.UserInputType === Enum.UserInputType.MouseButton1) ||
				(drag.kind === "touch" && input === drag.touch)
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
		const [guiInset] = game.GetService("GuiService").GetGuiInset();
		dragRef.current = {
			kind,
			touch: kind === "touch" ? input : undefined,
			pointer: new Vector2(input.Position.X, input.Position.Y),
			right: shell.AbsolutePosition.X + shell.AbsoluteSize.X + guiInset.X,
			top: shell.AbsolutePosition.Y + guiInset.Y,
		};
	}, []);
	const firstPage = model.pages[0];
	const [activePageId, setActivePageId] = React.useState(firstPage.id);
	const [visualView, setVisualView] = React.useState<"preview" | "colors">("preview");
	const activePage = model.pages.find((page) => page.id === activePageId) ?? firstPage;
	const visualsActive = activePage.id === "Visuals" && activePage.layout === "toggle-grid";
	React.useEffect(() => {
		if (model.pages.find((page) => page.id === activePageId) === undefined) setActivePageId(model.pages[0].id);
	}, [model.pages, activePageId]);
	const tabs = model.pages.map((page) => ({
		value: page.id,
		label: page.label,
		icon: page.icon,
	}));

	return (
		<ThemeProvider theme={HUB_THEME}>
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
				<uistroke Color={Color3.fromRGB(68, 68, 73)} Transparency={0.2} Thickness={1} />
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
								BackgroundTransparency={0}
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
							key="drag-handle"
							Active
							AutoButtonColor={false}
							BackgroundTransparency={1}
							BorderSizePixel={0}
							Size={UDim2.fromScale(1, 1)}
							Text=""
							TextTransparency={1}
							ZIndex={20}
							Event={{ InputBegan: (_button, input) => beginDrag(input) }}
						/>
					</frame>
					<frame
						BackgroundColor3={Color3.fromRGB(24, 24, 26)}
						BackgroundTransparency={0}
						BorderSizePixel={0}
						Position={UDim2.fromOffset(12, 64)}
						Size={new UDim2(1, -24, 0, 38)}
						ClipsDescendants={true}
						ZIndex={4}
					>
						<uicorner CornerRadius={new UDim(0, 8)} />
						<uistroke Color={Color3.fromRGB(68, 68, 73)} Transparency={0.18} Thickness={1} />
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
								tab: (_styles, context) => {
									const selected = context.state === "selected";
									const hovered = context.state === "hovered" || context.state === "focused";
									return {
										backgroundColor: selected ? context.theme.colors.action.pressed : context.theme.colors.action.hover,
										backgroundTransparency: selected ? 0.76 : hovered ? 0.62 : 1,
										strokeColor: context.theme.colors.border.subtle,
										strokeTransparency: 1,
										textColor: selected
											? context.theme.colors.primary.main
											: hovered
												? context.theme.colors.text.primary
												: context.theme.colors.text.secondary,
										textTransparency: 0,
										indicatorColor: context.theme.colors.primary.main,
										indicatorTransparency: 1,
									};
								},
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
								tabPadding: {
									PaddingLeft: new UDim(0, 2),
									PaddingRight: new UDim(0, 2),
								},
								tabIndicator: { Visible: false },
								panel: { Visible: false },
							}}
						/>
					</frame>
					{visualsActive && (
						<frame
							BackgroundTransparency={1}
							BorderSizePixel={0}
							Position={UDim2.fromOffset(24, 110)}
							Size={new UDim2(1, -48, 0, 32)}
							ZIndex={5}
						>
							<CompactSegments
								options={[
									{ value: "preview", label: "Preview" },
									{ value: "colors", label: "ESP Colors" },
								]}
								value={visualView}
								onChange={(value) => setVisualView(value as "preview" | "colors")}
							/>
						</frame>
					)}
					<ScrollArea
						width="100%"
						height={new UDim(1, visualsActive ? -150 : -110)}
						position={new UDim2(0, 0, 0, visualsActive ? 150 : 110)}
						direction="vertical"
						scrollbarSize={3}
					>
						<Box width="100%" p="xl">
							<SectionView page={activePage} model={model} visualView={visualView} />
						</Box>
					</ScrollArea>
				</frame>
			</frame>
		</ThemeProvider>
	);
}
