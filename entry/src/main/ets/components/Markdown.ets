import { Markdown as NativeMarkdown, MarkdownController } from '@luvi/lv-markdown-in';
import { Palette } from './Theme';

@Component
export struct Markdown {
  @Prop text: string = '';
  @Prop palette: Palette = new Palette(false);
  open: (url: string) => void = () => {};
  copy: (text: string) => void = () => {};
  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    const ink = this.palette.ink;
    this.controller
      .setTextColor(ink)
      .setTextSize(16)
      .setTextLineHeight(28)
      .setTitleColor(ink)
      .setTitleSize([24, 22, 20, 16, 16, 16])
      .setTitleLineHeight([34, 32, 30, 28, 28, 28])
      .setTitleFontWeight(FontWeight.Bold)
      .setInlineCodeColor(ink)
      .setInlineCodeBackgroundColor(this.palette.selector)
      .setQuoteTextColor(this.palette.muted)
      .setQuoteBorderColor(this.palette.placeholder)
      .setQuoteBackgroundColor(Color.Transparent)
      .setCodeBlockTheme(this.palette.dark ? 'dark' : 'light')
      .setCodeBlockBorderRadius(12)
      .setCodeBlockIdxState(false)
      .setCodeBlockAutoCollapseEnable(false)
      .setCodeCopyListener((text: string) => this.copy(text))
      .setHyperlinkTextColor(this.palette.brandText)
      .setHyperlinkClickListener((_title: string, url: string): boolean => {
        this.open(url);
        return true;
      })
      .setImageLoadProxy(() => '')
      .setImageClickListener(() => true)
      .setTableBackgroundColor(this.palette.background)
      .setTableTitleTextColor(ink)
      .setTableTitleBackgroundColor(this.palette.subtle)
      .setTableInterleaveBackgroundColor(this.palette.background)
      .setTableOuterBorderColor(this.palette.border)
      .setTableInnerBorderColor(this.palette.border)
      .setLatexMathTextSize(16)
      .setLatexMathTextColor(Number.parseInt('FF' + ink.slice(1), 16))
      .setMermaidEnable(false)
      .setHtmlPreviewEnable(false)
      .setWebPreviewPoolEnable(false)
      .setTextSelectionEnable(true)
      .setTextSelectionCopyListener((text: string) => this.copy(text));
    this.controller.setTableNormalTextColor(ink);
    this.controller.setTableInterleaveTextColor(ink);
    this.controller.setBlockSpacing(12);
  }

  build() {
    NativeMarkdown({ text: this.text, controller: this.controller })
      .width('100%')
      .height('auto')
  }
}
