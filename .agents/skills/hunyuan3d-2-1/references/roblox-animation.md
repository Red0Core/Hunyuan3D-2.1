# Image-to-Model in Roblox animation

Hunyuan produces a static textured surface from a picture. Use it when the task needs a recognizable handheld prop, furniture, a silhouette-heavy machine, a building exterior or background set dressing. It is strongest with the distinctive side of the object visible in the reference and a clear silhouette at the shot's actual size.

- **Background or medium shot:** generate the object from an isolated reference, verify the GLB and check it in the shot. A whole diorama is useful as one dressing asset when individual parts need no movement.
- **Handheld prop or close-up:** check contact surfaces, back geometry, scale, origin and attachment point in Blender. Treat lids, buttons and other moving parts as separate authored objects when they need to animate. Prefer a precise existing or modeled prop for mechanical fit, small text, brand geometry, or an extreme close-up.
- **Characters, costumes and motion:** use the project's authentic Roblox R6/R15 rigs and established animation workflow. A generated mesh is a static prop and carries no rig, facial controls, animation, seating or collision setup.
- **Project handoff:** retain the reference and raw GLB. Review material links and the visible side under shot lighting, then prepare a copy in the project pipeline. Test Roblox Studio separately if the request includes game use. The upstream agreement also applies to publishing and has territorial and usage terms for generated output. Check the [Tencent license](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/blob/main/LICENSE) for the planned release.

Follow the animation brief, shot framing and intended use to decide whether the prop merits a full generation and cleanup. For an existing approved asset, reuse the approved version unless the task calls for a replacement.
