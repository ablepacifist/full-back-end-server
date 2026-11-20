import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * Makes sure the HSQLDB "SA" account has the password configured in DATABASE_PASSWORD.
 *
 * Run by restart-all.ps1 right after the database starts (single-file launch, hsqldb.jar on the classpath):
 *   java -cp lib\hsqldb.jar scripts\HsqlEnsurePassword.java
 *
 * Reads DATABASE_URL and DATABASE_PASSWORD from the environment (never from the command line, so the
 * password does not show up in a process listing). Idempotent:
 *   - SA already accepts the configured password        -> nothing to do
 *   - SA still has the old empty password               -> set the configured password
 *   - neither works                                     -> report and fail (nothing is changed)
 *
 * Exit codes: 0 ok / nothing to do, 1 could not authenticate either way, 2 bad usage.
 */
public class HsqlEnsurePassword {

    public static void main(String[] args) throws Exception {
        String url = System.getenv("DATABASE_URL");
        String password = System.getenv("DATABASE_PASSWORD");
        if (url == null || url.isBlank()) {
            url = "jdbc:hsqldb:hsql://localhost:9002/mydb";
        }
        if (password == null || password.isEmpty()) {
            System.out.println("DATABASE_PASSWORD not set: leaving the database password unchanged.");
            return;
        }
        if (password.indexOf('\'') >= 0 || password.indexOf('\\') >= 0 || password.indexOf('\n') >= 0) {
            System.err.println("DATABASE_PASSWORD must not contain quotes, backslashes or newlines.");
            System.exit(2);
        }

        Class.forName("org.hsqldb.jdbc.JDBCDriver");

        if (canConnect(url, password)) {
            System.out.println("HSQLDB SA password is already set.");
            return;
        }
        try (Connection conn = DriverManager.getConnection(url, "SA", "");
                Statement stmt = conn.createStatement()) {
            stmt.execute("ALTER USER SA SET PASSWORD '" + password + "'");
            System.out.println("HSQLDB SA password has been set.");
        } catch (SQLException e) {
            System.err.println("Could not authenticate as SA with the configured password or an empty one: "
                    + e.getMessage());
            System.exit(1);
        }
    }

    private static boolean canConnect(String url, String password) {
        try (Connection ignored = DriverManager.getConnection(url, "SA", password)) {
            return true;
        } catch (SQLException e) {
            return false;
        }
    }
}
