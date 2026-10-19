{{flutter_js}}
{{flutter_build_config}}

// Run the app inside #flutter_host. CSS in index.html keeps that box inside
// the phone's safe area (clear of the notch, the gesture bar and rounded
// corners) while the page background fills the whole screen edge to edge.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.querySelector("#flutter_host"),
    });
    await appRunner.runApp();
  },
});
