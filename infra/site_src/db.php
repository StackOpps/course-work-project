<?php
function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO(
            sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', getenv('DB_HOST'), getenv('DB_NAME')),
            getenv('DB_USER'),
            getenv('DB_PASSWORD'),
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );
        // Safety net for a fresh (non-restored) database only — after a DR
        // restore this table and its rows already exist in the recovery point.
        $pdo->exec('CREATE TABLE IF NOT EXISTS signups (
            id INT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(255) NOT NULL,
            name VARCHAR(255),
            created_at DATETIME NOT NULL
        )');
    }
    return $pdo;
}
