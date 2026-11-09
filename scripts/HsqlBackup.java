import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;

/**
 * Takes a consistent snapshot of the running HSQLDB database with HSQLDB's own online backup.
 *
 * Run by backup-lexicon-db.ps1 (single-file launch, hsqldb.jar on the classpath):
 *   java -cp lexiconServer\lib\hsqldb.jar scripts\HsqlBackup.java <destination-directory>
 *
 * Reads DATABASE_URL and DATABASE_PASSWORD from the environment (never from the command line, so the
 * password does not show up in a process listing). The server writes a compressed .tar.gz holding
 * alchemydb.script and alchemydb.properties into the destination directory (on the machine the database
 * server runs on, which is this one). BLOCKING holds writes for the second or two the copy takes, so the
 * archive is a single point in time.
 *
 * Exit codes: 0 ok, 1 backup failed, 2 bad usage.
 */
public class HsqlBackup {

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("usage: HsqlBackup <destination-directory>");
            System.exit(2);
        }
        String url = System.getenv("DATABASE_URL");
        if (url == null || url.isBlank()) {
            url = "jdbc:hsqldb:hsql://localhost:9002/mydb";
        }
        String password = System.getenv("DATABASE_PASSWORD");
        if (password == null) {
            password = "";
        }
        String dest = args[0].replace('\\', '/');
        if (!dest.endsWith("/")) {
            dest = dest + "/";
        }
        if (dest.indexOf('\'') >= 0) {
            System.err.println("destination must not contain a quote");
            System.exit(2);
        }
        try (Connection conn = DriverManager.getConnection(url, "SA", password);
             Statement st = conn.createStatement()) {
            st.execute("BACKUP DATABASE TO '" + dest + "' BLOCKING");
            System.out.println("BACKUP OK");
        } catch (Exception e) {
            System.err.println("BACKUP FAILED: " + e.getMessage());
            System.exit(1);
        }
    }
}
