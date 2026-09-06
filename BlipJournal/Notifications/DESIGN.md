# Notifications

A2 replaces the no-op coordinator and settings screen. The main-actor protocol in
NotificationCoordinator.swift is the contract; pendingRoute stores a prompt ID.
No authorization request, scheduling, or routing occurs in A1.
