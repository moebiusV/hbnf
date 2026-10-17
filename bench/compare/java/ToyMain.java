// ToyMain.java — time ANTLR parsing the toy file: "cold" is the first parse in
// a fresh JVM, "warm" the last of four in the same JVM; "tree" builds the
// default parse tree instead of running the actions.  Output as timing.h.
import org.antlr.v4.runtime.*;
import java.nio.file.*;

public class ToyMain {
  public static void main(String[] a) throws Exception {
    String mode = a[0];
    String text = new String(Files.readAllBytes(Paths.get(a[1])), "UTF-8");
    int runs = mode.equals("warm") ? 4 : 1;
    double ms = 0;
    long count = 0, sum = 0;
    boolean ok = true;
    for (int i = 0; i < runs; i++) {
      long t0 = System.nanoTime();
      ToyLexer lx = new ToyLexer(CharStreams.fromString(text));
      ToyParser p = new ToyParser(new CommonTokenStream(lx));
      p.setBuildParseTree(mode.equals("tree"));
      p.removeErrorListeners();
      ToyParser.ConfigContext cfg = p.config();
      ms = (System.nanoTime() - t0) / 1e6;
      ok = p.getNumberOfSyntaxErrors() == 0;
      count = p.count;
      sum = p.long_sum;
      if (mode.equals("tree") && ok) {
        count = cfg.stmt().size();
        sum = 0;
        for (ToyParser.StmtContext r : cfg.stmt())
          sum += Long.parseLong(r.fp.getText()) + Long.parseLong(r.tp.getText());
      }
    }
    long rss = 0;
    for (String l : Files.readAllLines(Paths.get("/proc/self/status")))
      if (l.startsWith("VmHWM:")) rss = Long.parseLong(l.replaceAll("[^0-9]", ""));
    System.out.printf("%s %d %d %d %.2f %d%n", ok ? "ok" : "FAIL",
        text.length(), count, sum, ms, rss);
  }
}
