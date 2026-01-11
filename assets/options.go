components {
  id: "option"
  component: "/assets/option.script"
}
embedded_components {
  id: "options_label"
  type: "label"
  data: "size {\n"
  "  x: 640.0\n"
  "  y: 32.0\n"
  "}\n"
  "text: \"Label\"\n"
  "font: \"/assets/font/fp10px.font\"\n"
  "material: \"/builtins/fonts/label-df.material\"\n"
  ""
  position {
    z: 0.9
  }
}
embedded_components {
  id: "options_button"
  type: "sprite"
  data: "default_animation: \"\\351\\200\\211\\351\\241\\271\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/assets/ui/ui_atlas.atlas\"\n"
  "}\n"
  ""
  position {
    z: 0.8
  }
}
