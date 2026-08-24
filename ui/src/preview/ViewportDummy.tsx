import React from "@rbxts/react";
import { Text } from "@prism/components/Text";
import type { MenuPage } from "../contracts";

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

function accessoryOwned(part: Instance, dummy: Model): boolean {
	let ancestor = part.Parent;
	while (ancestor !== undefined && ancestor !== dummy) {
		if (ancestor.IsA("Accessory")) return true;
		ancestor = ancestor.Parent;
	}
	return false;
}

function project(camera: Camera, viewport: ViewportFrame, point: Vector3): Vector2 | undefined {
	const localPoint = camera.CFrame.PointToObjectSpace(point);
	const depth = -localPoint.Z;
	if (depth <= 0.01) return undefined;
	const size = viewport.AbsoluteSize;
	const focal = size.Y / (2 * math.tan(math.rad(camera.FieldOfView) * 0.5));
	const [inset] = game.GetService("GuiService").GetGuiInset();
	return viewport.AbsolutePosition.add(inset).add(
		new Vector2(size.X * 0.5 + (localPoint.X * focal) / depth, size.Y * 0.5 - (localPoint.Y * focal) / depth),
	);
}

function swatch(preview: MenuPage["preview"], id: string, fallback: Color3): Color3 {
	return (
		preview?.palette?.relationships
			.find((relationship) => relationship.id === "enemy")
			?.targets.find((target) => target.id === id)?.color ?? fallback
	);
}

export function ViewportDummy({
	preview,
	suspended = false,
}: {
	readonly preview?: MenuPage["preview"];
	readonly suspended?: boolean;
}): React.ReactElement {
	const [viewport, setViewport] = React.useState<ViewportFrame>();
	const [subject, setSubject] = React.useState<Model>();
	const [scene, setScene] = React.useState<{ dummy: Model; camera: Camera; world: WorldModel }>();
	const previewRef = React.useRef(preview);
	const yawRef = React.useRef(math.pi);
	const hoveredRef = React.useRef(false);
	const previousCursor = React.useRef<string>();
	const dragRef = React.useRef<InputObject>();
	previewRef.current = preview;

	const cursor = React.useCallback((dragging: boolean) => {
		const mouse = game.GetService("Players").LocalPlayer.GetMouse();
		if (previousCursor.current === undefined) previousCursor.current = mouse.Icon;
		mouse.Icon = dragging ? "rbxasset://SystemCursors/ClosedHand" : "rbxasset://SystemCursors/OpenHand";
	}, []);
	const restoreCursor = React.useCallback(() => {
		if (previousCursor.current === undefined) return;
		game.GetService("Players").LocalPlayer.GetMouse().Icon = previousCursor.current;
		previousCursor.current = undefined;
	}, []);

	React.useEffect(() => {
		let cancelled = false;
		setSubject(undefined);
		if (preview?.resolve === undefined) return;
		preview.report?.("resolving");
		task.spawn(() => {
			const [ok, result] = pcall(() => preview.resolve!());
			if (!ok || result === undefined || !result.IsA("Model")) {
				preview.report?.("resolve-failed", tostring(result));
				return;
			}
			if (cancelled) result.Destroy();
			else {
				preview.report?.("resolved");
				setSubject(result);
			}
		});
		return () => {
			cancelled = true;
		};
	}, [preview?.key]);

	React.useEffect(() => {
		if (viewport === undefined || (preview?.resolve !== undefined && subject === undefined)) return;
		let cancelled = false;
		const world = new Instance("WorldModel");
		world.Parent = viewport;
		const camera = new Instance("Camera");
		camera.FieldOfView = 28;
		camera.Parent = viewport;
		viewport.CurrentCamera = camera;
		task.spawn(() => {
			let dummy = subject;
			const players = game.GetService("Players");
			const character = players.LocalPlayer.Character;
			if (dummy === undefined) {
				const humanoid = character?.FindFirstChildOfClass("Humanoid");
				const description =
					humanoid !== undefined
						? humanoid.GetAppliedDescription()
						: players.GetHumanoidDescriptionFromUserIdAsync(players.LocalPlayer.UserId);
				const rig = humanoid?.RigType ?? Enum.HumanoidRigType.R15;
				for (let attempt = 1; attempt <= 3 && dummy === undefined && !cancelled; attempt += 1) {
					const [ok, result] = pcall(() => players.CreateHumanoidModelFromDescriptionAsync(description, rig));
					if (ok) dummy = result;
					else task.wait(attempt * 0.4);
				}
				description.Destroy();
			}
			if (dummy === undefined || cancelled) {
				dummy?.Destroy();
				return;
			}
			dummy.Name = "LimnPreviewAvatar";
			for (const item of dummy.GetDescendants()) {
				if (item.IsA("BasePart")) {
					item.CanCollide = false;
					item.CanQuery = false;
					item.CanTouch = false;
				} else if (item.IsA("Script") || item.IsA("LocalScript")) item.Destroy();
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
				const configuredIdle = character
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
			const [bounds, size] = dummy.GetBoundingBox();
			camera.CFrame = CFrame.lookAt(
				bounds.Position.add(new Vector3(0, 0, math.max(size.Y * 2.35, 7))),
				bounds.Position,
			);
			previewRef.current?.report?.("ready");
			setScene({ dummy, camera, world });
		});
		return () => {
			cancelled = true;
			setScene(undefined);
			camera.Destroy();
			world.Destroy();
		};
	}, [viewport, preview?.key, subject]);

	React.useEffect(() => {
		if (scene === undefined || preview?.worldRenderer !== "native" || preview.chams !== true) return;
		const folder = new Instance("Folder");
		folder.Name = "UniversalHubPreviewChams";
		folder.Parent = scene.world;
		const restores = new Array<() => void>();
		for (const part of scene.dummy.GetDescendants()) {
			if (!part.IsA("BasePart") || part.Transparency >= 1 || part.Name === "HumanoidRootPart") continue;
			if (preview.chamsExcludeAccessories === true && accessoryOwned(part, scene.dummy)) continue;
			const old = part.LocalTransparencyModifier;
			part.LocalTransparencyModifier = 1;
			restores.push(() => {
				if (part.Parent !== undefined) part.LocalTransparencyModifier = old;
			});
			const fill = part.Clone();
			fill.Material = Enum.Material.SmoothPlastic;
			fill.Color = preview.chamsColor ?? Color3.fromRGB(255, 118, 87);
			fill.Transparency = math.min(preview.chamsTransparency ?? 0.42, 0.22);
			fill.Size = fill.Size.mul(1.035);
			fill.CastShadow = false;
			fill.CanCollide = false;
			fill.CanQuery = false;
			fill.CanTouch = false;
			fill.Massless = true;
			if (fill.IsA("MeshPart")) fill.TextureID = "";
			for (const child of fill.GetDescendants())
				if (
					child.IsA("JointInstance") ||
					child.IsA("WeldConstraint") ||
					child.IsA("Decal") ||
					child.IsA("Texture") ||
					child.IsA("SurfaceAppearance")
				)
					child.Destroy();
			fill.CFrame = part.CFrame;
			fill.Parent = folder;
			const weld = new Instance("WeldConstraint");
			weld.Part0 = part;
			weld.Part1 = fill;
			weld.Parent = fill;
		}
		return () => {
			for (const restore of restores) restore();
			folder.Destroy();
		};
	}, [
		scene,
		preview?.worldRenderer,
		preview?.chams,
		preview?.chamsExcludeAccessories,
		preview?.chamsColor,
		preview?.chamsTransparency,
	]);

	React.useEffect(() => {
		if (scene === undefined || preview?.worldRenderer !== "native" || preview.boxes !== true) return;
		const folder = new Instance("Folder");
		folder.Name = "UniversalHubPreviewHitboxes";
		folder.Parent = scene.world;
		for (const part of scene.dummy.GetDescendants()) {
			if (!part.IsA("BasePart") || part.Transparency >= 1 || part.Name === "HumanoidRootPart") continue;
			if (preview.chamsExcludeAccessories === true && accessoryOwned(part, scene.dummy)) continue;
			const box = new Instance("SelectionBox");
			box.Adornee = part;
			box.Color3 = preview.outlineColor ?? Color3.fromRGB(255, 118, 87);
			box.LineThickness = 0.05;
			box.SurfaceTransparency = 1;
			box.Parent = folder;
		}
		return () => folder.Destroy();
	}, [scene, preview?.worldRenderer, preview?.boxes, preview?.chamsExcludeAccessories, preview?.outlineColor]);

	React.useEffect(() => {
		if (viewport === undefined || scene === undefined) return;
		if (
			suspended ||
			!(
				preview?.boxes === true ||
				preview?.chams === true ||
				preview?.names === true ||
				preview?.health === true ||
				preview?.weapon === true
			)
		) {
			previewRef.current?.publish?.(undefined);
			return;
		}
		const connection = game.GetService("RunService").RenderStepped.Connect(() => {
			const current = previewRef.current;
			if (current?.publish === undefined) return;
			const bodyParts = new Array<{ visible: true; corners: Vector2[]; accessory?: true }>();
			let minimum = new Vector2(math.huge, math.huge);
			let maximum = new Vector2(-math.huge, -math.huge);
			for (const part of scene.dummy.GetDescendants()) {
				if (!part.IsA("BasePart") || part.Transparency >= 1 || part.Name === "HumanoidRootPart") continue;
				const accessory = accessoryOwned(part, scene.dummy);
				if (accessory && current.worldRenderer !== "native") continue;
				const corners = new Array<Vector2>();
				const half = part.Size.mul(0.5);
				for (const sign of PART_CORNERS) {
					const point = project(
						scene.camera,
						viewport,
						part.CFrame.PointToWorldSpace(new Vector3(half.X * sign.X, half.Y * sign.Y, half.Z * sign.Z)),
					);
					if (point === undefined) break;
					corners.push(point);
					minimum = new Vector2(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y));
					maximum = new Vector2(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y));
				}
				if (corners.size() === PART_CORNERS.size())
					bodyParts.push({ visible: true, corners, accessory: accessory ? true : undefined });
			}
			if (bodyParts.size() > 0)
				current.publish({ bounds: { position: minimum, size: maximum.sub(minimum) }, bodyParts });
		});
		return () => {
			connection.Disconnect();
			previewRef.current?.publish?.(undefined);
		};
	}, [viewport, scene, suspended, preview?.boxes, preview?.chams, preview?.names, preview?.health, preview?.weapon]);

	React.useEffect(() => {
		const changed = UserInputService.InputChanged.Connect((input) => {
			if (
				dragRef.current === undefined ||
				(input !== dragRef.current && input.UserInputType !== Enum.UserInputType.MouseMovement) ||
				scene === undefined
			)
				return;
			yawRef.current += input.Delta.X * 0.012;
			scene.dummy.PivotTo(CFrame.Angles(0, yawRef.current, 0));
		});
		const ended = UserInputService.InputEnded.Connect((input) => {
			if (input === dragRef.current || input.UserInputType === Enum.UserInputType.MouseButton1) {
				dragRef.current = undefined;
				if (hoveredRef.current) cursor(false);
				else restoreCursor();
			}
		});
		return () => {
			changed.Disconnect();
			ended.Disconnect();
			restoreCursor();
		};
	}, [scene, cursor, restoreCursor]);

	const labels = preview?.worldRenderer === "native" && (preview.names || preview.health || preview.weapon);
	const health = swatch(preview, "healthLow", Color3.fromRGB(255, 118, 87)).Lerp(
		swatch(preview, "healthHigh", Color3.fromRGB(98, 214, 173)),
		0.72,
	);
	return (
		<React.Fragment>
			<viewportframe
				ref={setViewport}
				Ambient={
					preview?.worldRenderer === "native" && preview.chams
						? Color3.fromRGB(255, 255, 255)
						: Color3.fromRGB(175, 165, 160)
				}
				LightColor={
					preview?.worldRenderer === "native" && preview.chams
						? Color3.fromRGB(0, 0, 0)
						: Color3.fromRGB(255, 205, 190)
				}
				LightDirection={new Vector3(-1, -1, -1)}
				BackgroundTransparency={1}
				BorderSizePixel={0}
				Size={UDim2.fromScale(1, 1)}
			/>
			{labels && (
				<frame key="UniversalHubPreviewLabels" BackgroundTransparency={1} Size={UDim2.fromScale(1, 1)} ZIndex={4}>
					{preview?.names && <Text text={preview.nameLabel ?? "Preview Player"} color={swatch(preview, "name", Color3.fromRGB(255, 118, 87))} width="100%" height={28} />}
					{preview?.health && <Text text="72 HP" color={health} position={new UDim2(0, 0, 1, -52)} width="100%" height={18} />}
					{preview?.weapon && <Text text={preview.weaponLabel ?? "Assault Rifle"} color={swatch(preview, "weapon", Color3.fromRGB(177, 188, 199))} position={new UDim2(0, 0, 1, -34)} width="100%" height={18} />}
				</frame>
			)}
			<textbutton
				Active
				AutoButtonColor={false}
				BackgroundTransparency={1}
				Size={UDim2.fromScale(1, 1)}
				Text=""
				ZIndex={5}
				Event={{
					InputBegan: (_button, input) => {
						if (input.UserInputType === Enum.UserInputType.MouseButton1 || input.UserInputType === Enum.UserInputType.Touch) {
							dragRef.current = input;
							cursor(true);
						}
					},
					MouseEnter: () => {
						hoveredRef.current = true;
						cursor(dragRef.current !== undefined);
					},
					MouseLeave: () => {
						hoveredRef.current = false;
						if (dragRef.current === undefined) restoreCursor();
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
