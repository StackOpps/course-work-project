<?php
require __DIR__ . '/db.php';
$rows = db()->query('SELECT id, email, name, created_at FROM signups ORDER BY id DESC')->fetchAll(PDO::FETCH_ASSOC);
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CraftHaven — Waitlist signups (live from RDS)</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; background:#171c15; color:#ece6d6; padding:2.5rem 1.5rem; }
  a { color:#d59a3c; }
  h1 { color:#ece6d6; font-size:1.4rem; margin-bottom:0.4rem; }
  .count { color:#b7ae98; margin-bottom:1.5rem; font-size:0.9rem; }
  table { border-collapse: collapse; width:100%; max-width:48rem; }
  th, td { border:1px solid #333a2c; padding:0.55rem 0.9rem; text-align:left; font-size:0.9rem; }
  th { color:#b7ae98; text-transform:uppercase; font-size:0.72rem; letter-spacing:0.05em; }
</style>
</head>
<body>
<p><a href="/">&larr; Back to storefront</a></p>
<h1>Waitlist signups</h1>
<p class="count"><?= count($rows) ?> row(s) currently in RDS — this page reads the database directly, so it proves the data came back after a restore, not just the web server.</p>
<table>
<tr><th>ID</th><th>Email</th><th>Name</th><th>Created (UTC)</th></tr>
<?php foreach ($rows as $r): ?>
<tr>
  <td><?= htmlspecialchars((string) $r['id']) ?></td>
  <td><?= htmlspecialchars($r['email']) ?></td>
  <td><?= htmlspecialchars($r['name'] ?? '') ?></td>
  <td><?= htmlspecialchars($r['created_at']) ?></td>
</tr>
<?php endforeach; ?>
</table>
</body>
</html>
