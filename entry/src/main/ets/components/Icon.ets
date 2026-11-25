@Component
export struct DemoIcon {
  @Prop glyph: Resource = $r('app.media.demo_menu');
  @Prop iconSize: number = 16;
  @Prop tint: string = '#0F1115';

  build() {
    Image(this.glyph)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.tint)
      .draggable(false)
      .accessibilityLevel('no')
  }
}
