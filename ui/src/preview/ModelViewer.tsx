import React from "@rbxts/react";
import { Text } from "@prism/components/Text";
import { theme } from "@prism/theme";
import type { ModelViewerControl } from "../contracts";

const UserInputService = game.GetService("UserInputService");

export function ModelViewer({ control }: { readonly control: ModelViewerControl }): React.ReactElement {
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
		camera.CFrame = CFrame.lookAt(
			target.add(rotation.VectorToWorldSpace(new Vector3(0, 0, distanceRef.current))),
			target,
		);
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

	const begin = (input: InputObject) => {
		const inputType = input.UserInputType;
		if (
			inputType !== Enum.UserInputType.MouseButton1 &&
			inputType !== Enum.UserInputType.MouseButton2 &&
			inputType !== Enum.UserInputType.Touch
		)
			return;
		dragRef.current = {
			kind:
				inputType === Enum.UserInputType.MouseButton2 ||
				UserInputService.IsKeyDown(Enum.KeyCode.LeftShift) ||
				UserInputService.IsKeyDown(Enum.KeyCode.RightShift)
					? "pan"
					: "orbit",
			input,
			pointer: new Vector2(input.Position.X, input.Position.Y),
		};
	};

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
					MouseEnter: () => (hoveredRef.current = true),
					MouseLeave: () => (hoveredRef.current = false),
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
