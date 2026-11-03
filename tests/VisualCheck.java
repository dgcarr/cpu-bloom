import processing.core.*;
import java.util.*;
public class VisualCheck extends cpu_bloom {
  String selected = System.getenv().getOrDefault("VISUAL_THEME", "bloom");
  public int millis() { return frameCount * 16; }
  public void settings() { size(820,820,P2D); smooth(4); }
  public void setup() {
    colorMode(HSB,360,100,100,100);
    randomSeed(42); noiseSeed(42);
    sampler = new SystemSampler();
    Arrays.fill(sampler.usage,0.5f);
    sampler.memUsedGiB=16;sampler.memTotalGiB=32;
    sampler.tempC=60;sampler.gpuSeen=true;sampler.gpuUtil=25;
    if(selected.equals("bloom"))theme=new BloomTheme();
    else theme=new RidgeTheme();
    theme.start();
    if (theme instanceof BloomTheme) {
      Bloom b=((BloomTheme)theme).bloom;
      for(int i=0;i<b.n;i++) for(int j=0;j<b.HISTORY;j++) b.history[i][j]=(float)(0.5+0.4*Math.sin(i+j*0.2));
    }
  }
  public void draw() {
    pushStyle();blendMode(BLEND);theme.draw(false);blendMode(BLEND);popStyle();
    if(frameCount==120) {save(System.getenv("VISUAL_OUTPUT"));exit();}
  }
  public static void main(String[] args) { PApplet.runSketch(new String[]{"VisualCheck"},new VisualCheck()); }
}
