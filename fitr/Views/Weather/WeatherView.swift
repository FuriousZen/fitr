//
//  WeatherView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI

struct WeatherView: View {
    let weather: Weather
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                weatherIcon
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.davyGrey)
                
                VStack(alignment: .leading) {
                    Text("\(Int(weather.temperature))°F")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppColors.davyGrey)
                    
                    Text(weather.condition.rawValue)
                        .font(.headline)
                        .foregroundColor(AppColors.davyGrey.opacity(0.8))
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(weather.location)
                        .font(.headline)
                        .foregroundColor(AppColors.davyGrey)
                    
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundColor(AppColors.davyGrey.opacity(0.8))
                }
            }
            
            HStack(spacing: 20) {
                WeatherDetailItem(icon: "humidity", value: "\(weather.humidity)%", label: "Humidity")
                
                WeatherDetailItem(icon: "wind", value: "\(Int(weather.windSpeed)) mph", label: "Wind")
            }
            .padding(.top, 5)
        }
        .padding()
        .background(weatherBackgroundColor.opacity(0.2))
        .cornerRadius(15)
    }
    
    var weatherIcon: some View {
        switch weather.condition {
        case .sunny:
            return Image(systemName: "sun.max.fill")
        case .cloudy:
            return Image(systemName: "cloud.fill")
        case .rainy:
            return Image(systemName: "cloud.rain.fill")
        case .snowy:
            return Image(systemName: "cloud.snow.fill")
        case .stormy:
            return Image(systemName: "cloud.bolt.fill")
        case .windy:
            return Image(systemName: "wind")
        case .foggy:
            return Image(systemName: "cloud.fog.fill")
        }
    }
    
    var weatherBackgroundColor: Color {
        switch weather.condition {
        case .sunny:
            return AppColors.peachSnaps
        case .cloudy:
            return AppColors.moonMist
        case .rainy, .foggy:
            return AppColors.davyGrey.opacity(0.5)
        case .snowy:
            return AppColors.moonMist
        case .stormy:
            return AppColors.davyGrey
        case .windy:
            return AppColors.springRain
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: weather.date)
    }
}

struct WeatherDetailItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon == "humidity" ? "drop.fill" : "wind")
                .foregroundColor(AppColors.davyGrey.opacity(0.7))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.davyGrey)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(AppColors.davyGrey.opacity(0.7))
            }
        }
    }
}
