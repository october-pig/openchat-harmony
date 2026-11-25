@Component
struct WaitingDot {
  @Prop tint: ResourceColor = Color.Gray;
  @Prop delay: number = 0;
  @State private bright: boolean = false;

  build() {
    Circle({ width: 6, height: 6 })
      .fill(this.tint)
      .opacity(this.bright ? 1 : 0.3)
      .animation({
        duration: 450,
        delay: this.delay,
        iterations: -1,
        playMode: PlayMode.Alternate,
        curve: Curve.EaseInOut
      })
      .onAppear(() => this.bright = true)
  }
}

@Component
export struct WaitingDots {
  @Prop tint: ResourceColor = Color.Gray;

  build() {
    Row({ space: 6 }) {
      WaitingDot({ tint: this.tint })
      WaitingDot({ tint: this.tint, delay: 100 })
      WaitingDot({ tint: this.tint, delay: 200 })
    }.accessibilityLevel('no')
  }
}
