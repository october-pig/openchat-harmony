export class Palette {
  readonly dark: boolean;
  background: string;
  surface: string;
  subtle: string;
  ink: string;
  muted: string;
  tertiary: string;
  placeholder: string;
  border: string;
  accent: string;
  accentText: string = '#FFFFFF';
  accentSoft: string;
  activeBorder: string;
  brandText: string;
  error: string;
  sidebar: string;
  input: string;
  field: string;
  bubble: string;
  hover: string;
  selector: string;
  sidebarActive: string;
  overlay: string;
  shadowColor: string;

  constructor(dark: boolean) {
    this.dark = dark;
    this.background = dark ? '#151517' : '#FFFFFF';
    this.surface = dark ? '#2C2C2E' : '#FFFFFF';
    this.subtle = dark ? '#2C2C2E' : '#F9FAFB';
    this.ink = dark ? '#F9FAFB' : '#0F1115';
    this.muted = dark ? '#CFD3D6' : '#61666B';
    this.tertiary = dark ? '#ADB2B8' : '#81858C';
    this.placeholder = dark ? '#81858C' : '#ADB2B8';
    this.border = dark ? '#1FFFFFFF' : '#1A000000';
    this.accent = dark ? '#5686FE' : '#3964FE';
    this.brandText = dark ? '#679EFE' : '#3964FE';
    this.accentSoft = dark ? '#283142' : '#EDF3FE';
    this.activeBorder = dark ? '#4868B2' : '#B7C8FE';
    this.error = dark ? '#F25A5A' : '#EC1313';
    this.sidebar = dark ? '#1B1B1C' : '#F9FAFB';
    this.input = dark ? '#2C2C2E' : '#FFFFFF';
    this.field = dark ? '#1B1B1C' : '#F9FAFB';
    this.bubble = dark ? '#2C2C2E' : '#EDF3FE';
    this.hover = dark ? '#14FFFFFF' : '#0F263148';
    this.selector = dark ? '#43454A' : '#F1F3F5';
    this.sidebarActive = dark ? '#353638' : '#E4EDFD';
    this.shadowColor = dark ? '#00000000' : '#0A4868B2';
    this.overlay = dark ? '#99000000' : '#5C000000';
  }
}
