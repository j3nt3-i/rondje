import SwiftUI

// Illustrations for the welcome carousel, drawn from shapes and symbols in the app's style.

private let lime = Color(red: 0.66, green: 1.0, blue: 0.0)
private let card = Color(white: 0.13)
private let zone2 = Color.cyan, zone3 = Color.green, zone4 = Color.orange

/// 1: a goal. A ring closing in on the finish flag, with the race date floating by.
struct GoalArt: View {
    var body: some View {
        ZStack {
            Circle().stroke(lime.opacity(0.15), lineWidth: 22).frame(width: 190, height: 190)
            Circle().trim(from: 0, to: 0.78)
                .stroke(lime, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 190, height: 190)
            Circle().fill(lime.opacity(0.12)).frame(width: 120, height: 120)
            Image(systemName: "flag.checkered")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(lime)
            chip(top: "Zo 13 dec", bottom: "nog 18 dagen")
                .offset(x: 112, y: -78)
            HStack(spacing: 6) {
                Image(systemName: "figure.run").foregroundStyle(lime)
                Text("15 km").foregroundStyle(.white)
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(card, in: Capsule())
            .offset(x: -110, y: 84)
        }
        .frame(width: 320, height: 260)
    }

    private func chip(top: String, bottom: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Text(bottom).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(lime)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
    }
}

/// 2: a schedule. A chat message turns into workout cards with zone colors.
struct ScheduleArt: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 8) {
                Text("Maak een schema voor de Devil's Trail")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(width: 128, alignment: .leading)
                    .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("AI")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(lime)
            VStack(spacing: 8) {
                workout("Heuvels", "Di 1 dec", [zone2, zone4, zone2], icon: "mountain.2.fill", color: .green)
                workout("Racetempo", "Do 3 dec", [zone2, zone3, zone2], icon: "stopwatch.fill", color: .orange)
                workout("Duurloop", "Zo 6 dec", [zone2], icon: "figure.run", color: .cyan)
            }
        }
        .frame(width: 340, height: 260)
    }

    private func workout(_ name: String, _ day: String, _ zones: [Color], icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                Text(day).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                        Capsule().fill(z).frame(width: i == 1 && zones.count > 1 ? 26 : 12, height: 5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 160)
        .background(card, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 3: every morning. A Watch with today's workout, and the sun coming up.
struct WatchArt: View {
    var body: some View {
        ZStack {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 38))
                .foregroundStyle(.yellow)
                .offset(x: 112, y: -92)
            // band
            RoundedRectangle(cornerRadius: 30).fill(Color(white: 0.12)).frame(width: 112, height: 250)
            // case
            RoundedRectangle(cornerRadius: 46)
                .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 168, height: 200)
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.3)).frame(width: 12, height: 36).offset(x: 88, y: -26)
            // screen
            RoundedRectangle(cornerRadius: 38).fill(.black).frame(width: 148, height: 180)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(lime).frame(width: 10, height: 10)
                    Text("Rondje").font(.system(size: 12, weight: .bold)).foregroundStyle(lime)
                }
                Text("5x 3 min").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Vandaag").font(.system(size: 11, weight: .bold)).foregroundStyle(lime)
                VStack(alignment: .leading, spacing: 5) {
                    step("10 min", zone2)
                    step("5x 3 min", zone4)
                    step("2 min", zone2)
                }
                .padding(.top, 2)
            }
            .frame(width: 118, alignment: .leading)
        }
        .frame(width: 320, height: 260)
    }

    private func step(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 4, height: 14)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
    }
}
