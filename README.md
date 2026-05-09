# Natural-Disaster-Notifier-Application
DisasterAlert is a cross-platform mobile application that delivers real-time disaster alerts across 180+ countries.Built with Flutter and Firebase, it integrates live data from the USGS Earthquake API, NASA EONET v3, and Open-Meteo to monitor and notify users of nearby disasters based on their location Developed as a solo capstone project.

This project demonstrates real-time API integration, mobile background services, Firebase cloud infrastructure, and production-level state management in a solo capstone build.

🌱 What I Learned
Flutter & Dart (Mobile Development)

How to architect a full mobile app using GetX for state management and dependency injection.
How to run background tasks using Android Background Service and Dart Isolates.
How to store user preferences locally with SharedPreferences.
How to trigger and manage push notifications with flutter_local_notifications.
Firebase (Cloud Infrastructure)

How to authenticate users securely with Firebase Authentication.
How to structure and query real-time data using Cloud Firestore.
How to manage user-specific data and alert preferences in the cloud.
API Integration

How to consume and merge data from three simultaneous live APIs: USGS Earthquake API, NASA EONET v3, and Open-Meteo.
How to calculate proximity-based alerts using the Haversine formula.
How to handle API failures gracefully without breaking the user experience.
Testing & Quality Assurance

How to write and execute structured test cases achieving an 11/11 pass rate.
How to validate real-time data accuracy and edge case handling across different disaster types and regions.

⚡ Features
Real-time disaster alerts covering earthquakes, wildfires, and severe weather events.
Global coverage across 180+ countries with location-based proximity filtering.
Background monitoring that continues alerting even when the app is closed.
Push notifications with severity classification and event details.
Firebase-powered user accounts with personalized alert preferences.
Offline resilience with local data caching via SharedPreferences.

🏆 Why This Project Matters
DisasterAlert is my undergraduate capstone project, built entirely solo from concept to deployment.

It is not a tutorial follow-along or a CRUD exercise. Every architectural decision — from choosing Dart Isolates for background processing to merging three live data sources into a unified alert system — was made independently and justified through research and testing.

The 100% test case pass rate reflects a commitment to reliability in a domain where inaccurate information has real consequences.

It represents the most complete and technically ambitious project I have built, and the one I am most proud of.
