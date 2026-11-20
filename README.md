# DitherPhil

DitherPhil is a native photo and video dithering editor for iPhone and iPad. The preview, comparison control and editing panel stay on the same screen. Rendering takes place on the device.

## Editing

- Open a photo or video from Photos or Files. The editor opens with a bundled sample so the controls are available immediately.
- Choose Threshold, Bayer 2 × 2, 4 × 4 or 8 × 8, Stipple, Atkinson, Floyd–Steinberg or Sierra Lite.
- Use source colors, adjustable grayscale, the Paper, Handheld and Amber palettes, or a custom shadow and highlight pair. Adjust the cell size, strength and blend.
- Adjust exposure, contrast, saturation and warmth. Invert the image or compare with the original.
- Export photos as PNG, JPEG or HEIC. PNG preserves transparency. Export video as MP4 with HEVC or H.264 and an audio track when present. Choose the original resolution or cap the longest edge at 3840, 1920, 1280 or 640 pixels.
- Use the system share sheet to save or send the rendered file. Export is SDR.

## Build

Open `DitherPhil.xcodeproj` and run the `DitherPhil` scheme. The app requires iOS 26 or later. The project uses Xcode 27.2 and the Xcode Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`). No package dependencies are required. When adding source files, regenerate the checked-in project with `xcodegen generate`.

The test scheme covers the eight algorithms, image formats, transparent PNGs, portrait video and audio, and the editor’s export flow. Use an iOS simulator with Metal support.

## Rendering

A reusable Metal-backed Core Image context performs color adjustments, ordered dithering, stippling and image scaling. Error diffusion uses three rolling rows of errors and alternates the scan direction. Photo previews cache a decoded thumbnail. Video previews use a reduced render size and cap playback at 30 fps, while exports use the selected dimensions and source frame timing. AVFoundation handles decoding and encoding.

The interface uses the [kpem design system](https://kpeeem.github.io/design). The bundled Iosevka Aile subset is distributed under the [SIL Open Font License](App/OFL-Iosevka.txt).
