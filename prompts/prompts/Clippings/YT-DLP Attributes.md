---
title: "YT-DLP Attributes"
source: "https://gemini.google.com/app/c5b42828e2d83aee"
author:
  - "[[Gemini]]"
published:
created: 2026-03-24
description: "Meet Gemini, Google's AI assistant. Get help with writing, planning, brainstorming and more. Experience the power of generative AI."
tags:
  - "clippings"
---
Because `yt-dlp` is a "wrapper" that interprets the raw JSON data provided by YouTube's internal APIs, the list of available attributes is extensive. For any given video, there are over **50 standard fields** and hundreds of format-specific ones.

### **The "Core" Analytics Attributes**

Beyond the four you've already mapped, these are the most critical for a data-driven project like **InsightCircle**:

- **`view_count`**: Total views (Integer).
- **`like_count`**: Total likes (Integer).
- **`comment_count`**: Number of comments (Integer).
- **`duration`**: Length of the video in seconds (Integer).
- **`upload_date`**: Upload date in `YYYYMMDD` (String).
- **`uploader` / `uploader_id`**: The name and unique ID of the channel.
- **`channel_follower_count`**: Total subscribers of the channel at the time of extraction.

### **Content & SEO Attributes**

These help you categorize the "Consortium" content for better indexing:

- **`description`**: The full text in the video description.
- **`tags`**: A list of keywords defined by the creator (e.g., "FHIR", "HealthTech").
- **`categories`**: Broad YouTube categories (e.g., "Science & Technology").
- **`playable_in_embed`**: Boolean indicating if the video can be embedded elsewhere.
- **`live_status`**: Identifies if the video was a "was\_live" stream or a standard upload.

### **Technical & Quality Attributes**

If you ever move into video processing or storage optimization:

- **`resolution`**: The highest available resolution (e.g., "1080p").
- **`fps`**: Frames per second.
- **`vcodec` / `acodec`**: The video and audio compression formats.
- **`filesize_approx`**: Estimated size of the file before downloading.