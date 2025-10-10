# fitr - Your Personal Outfit Assistant

Never struggle with "what to wear" again. fitr uses AI to generate perfect outfit recommendations based on your wardrobe, current weather, and mood.

## What is fitr?

fitr is an iOS app that solves the daily dilemma of choosing what to wear. By combining your personal wardrobe with real-time weather data and your current mood, it generates intelligent outfit recommendations that are both stylish and practical.

## Features

- **Smart Outfit Generation**: Get personalized outfit recommendations using AI
- **Weather-Aware**: Automatically considers local weather conditions
- **Mood-Based Styling**: Express your vibe and get outfits that match
- **Wardrobe Management**: Organize and categorize your clothing items
- **Laundry Tracking**: Keep track of clean vs. dirty clothes
- **Photo Recognition**: Automatically classify clothing items from photos

## Screenshots

<img src="assets/login.png" alt="Login Screen" width="150"> <img src="assets/gallery.png" alt="Gallery View" width="150">

<img src="assets/vibe.png" alt="Mood Selection" width="150"> <img src="assets/outfit_details.png" alt="Outfit Details" width="150">

<img src="assets/wardrobe.png" alt="Wardrobe Management" width="150">

## How We Built It

This project was built in less than a day during Hoohacks hackathon. We used XCode and Apple's SwiftUI to build the app. We leveraged Google Gemini 1.5 Pro for image recognition/classification and generating outfits. We also used OpenWeatherMap's API for real-time weather coverage at our current location to pass in as an additional parameter for creating outfits.

### Tech Stack
- **Frontend**: SwiftUI
- **AI/ML**: Google Gemini 1.5 Pro
- **Weather Data**: OpenWeatherMap API
- **Backend**: Firebase Cloud Storage
- **Image Processing**: Core ML

## Contributing

We welcome contributions! Please feel free to submit a Pull Request.

## Roadmap

- Custom ML model specialized for clothing recognition
- Enhanced user preference learning
- Social features for outfit sharing
- Integration with fashion retailers
- Advanced styling algorithms
