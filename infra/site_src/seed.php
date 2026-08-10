<?php
// CLI-only: seeds realistic-looking signups for DR drills, not a web
// endpoint like signup.php/signups.php — nothing routes .php requests to
// PHP CLI, but this guard keeps it that way if that ever changes.
if (php_sapi_name() !== 'cli') {
    http_response_code(403);
    exit("seed.php is CLI-only\n");
}

require __DIR__ . '/db.php';

$count = isset($argv[1]) ? (int) $argv[1] : 500;
$count = max(1, min($count, 20000));

$firstNames = ['Olivia', 'Liam', 'Emma', 'Noah', 'Ava', 'Oliver', 'Sophia', 'Elijah', 'Isabella', 'James', 'Mia', 'Benjamin', 'Charlotte', 'Lucas', 'Amelia', 'Henry', 'Harper', 'Alexander', 'Evelyn', 'Mason', 'Aria', 'Ethan', 'Ella', 'Jacob', 'Scarlett', 'Michael', 'Grace', 'Daniel', 'Chloe', 'Matthew'];
$lastNames  = ['Smith', 'Jones', 'Taylor', 'Brown', 'Williams', 'Wilson', 'Johnson', 'Davies', 'Robinson', 'Wright', 'Thompson', 'Evans', 'Walker', 'White', 'Roberts', 'Green', 'Hall', 'Wood', 'Jackson', 'Clarke', 'Kelly', 'Baker', 'Hughes', 'Edwards', 'Hill', 'Moore', 'Cook', 'Ward', 'Turner', 'Adams'];
$domains    = ['gmail.com', 'outlook.com', 'yahoo.com', 'icloud.com', 'proton.me', 'hotmail.com'];

$pdo = db();
$stmt = $pdo->prepare('INSERT INTO signups (email, name, created_at) VALUES (?, ?, ?)');

// Spread over the last 90 days rather than one timestamp, so a restored
// table looks like an organically grown waitlist instead of a seeding burst.
$now = new DateTimeImmutable('now', new DateTimeZone('UTC'));

$pdo->beginTransaction();
for ($i = 0; $i < $count; $i++) {
    $first = $firstNames[array_rand($firstNames)];
    $last  = $lastNames[array_rand($lastNames)];
    $email = strtolower($first . '.' . $last . random_int(1, 9999) . '@' . $domains[array_rand($domains)]);
    $createdAt = $now->modify('-' . random_int(0, 90 * 86400) . ' seconds')->format('Y-m-d H:i:s');
    $stmt->execute([$email, "$first $last", $createdAt]);
}
$pdo->commit();

echo "Inserted $count signups.\n";
