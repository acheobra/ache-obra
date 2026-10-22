importScripts('https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyDQnBjfd227j31b-OHh7xfMC6aS6sMe6tY",
  projectId: "ache-obra",
  messagingSenderId: "124276513752",
  appId: "1:124276513752:android:4078a17fa75d4a30c730ad"
});

const messaging = firebase.messaging();