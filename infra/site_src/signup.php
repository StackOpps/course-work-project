<?php
header('Content-Type: application/json');
require __DIR__ . '/db.php';

$input = json_decode(file_get_contents('php://input'), true) ?: $_POST;
$email = trim($input['email'] ?? '');
$name = trim($input['name'] ?? '');

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode(['error' => 'A valid email is required']);
    exit;
}

try {
    $stmt = db()->prepare('INSERT INTO signups (email, name, created_at) VALUES (?, ?, UTC_TIMESTAMP())');
    $stmt->execute([$email, $name !== '' ? $name : null]);
    echo json_encode(['ok' => true, 'id' => db()->lastInsertId()]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Could not save signup']);
}
