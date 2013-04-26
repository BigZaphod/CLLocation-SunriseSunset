/*
 * Copyright (c) 2013, The Iconfactory. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of The Iconfactory nor the names of its contributors may
 *    be used to endorse or promote products derived from this software without
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE ICONFACTORY BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "CLLocation+SunriseSunset.h"
#import <Foundation/Foundation.h>

/*******************************************************************************************

 http://williams.best.vwh.net/sunrise_sunset_algorithm.htm

 Sunrise/Sunset Algorithm
 
 Source:
 Almanac for Computers, 1990
 published by Nautical Almanac Office
 United States Naval Observatory
 Washington, DC 20392
 
 Inputs:
 day, month, year:      date of sunrise/sunset
 latitude, longitude:   location for sunrise/sunset
 zenith:                Sun's zenith for sunrise/sunset
 offical      = 90 degrees 50'
 civil        = 96 degrees
 nautical     = 102 degrees
 astronomical = 108 degrees
 
 NOTE: longitude is positive for East and negative for West
 NOTE: the algorithm assumes the use of a calculator with the
 trig functions in "degree" (rather than "radian") mode. Most
 programming languages assume radian arguments, requiring back
 and forth convertions. The factor is 180/pi. So, for instance,
 the equation RA = atan(0.91764 * tan(L)) would be coded as RA
 = (180/pi)*atan(0.91764 * tan((pi/180)*L)) to give a degree
 answer with a degree input for L.
 
 
 1. first calculate the day of the year
 
 N1 = floor(275 * month / 9)
 N2 = floor((month + 9) / 12)
 N3 = (1 + floor((year - 4 * floor(year / 4) + 2) / 3))
 N = N1 - (N2 * N3) + day - 30
 
 2. convert the longitude to hour value and calculate an approximate time
 
 lngHour = longitude / 15
 
 if rising time is desired:
 t = N + ((6 - lngHour) / 24)
 if setting time is desired:
 t = N + ((18 - lngHour) / 24)
 
 3. calculate the Sun's mean anomaly
 
 M = (0.9856 * t) - 3.289
 
 4. calculate the Sun's true longitude
 
 L = M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634
 NOTE: L potentially needs to be adjusted into the range [0,360) by adding/subtracting 360
 
 5a. calculate the Sun's right ascension
 
 RA = atan(0.91764 * tan(L))
 NOTE: RA potentially needs to be adjusted into the range [0,360) by adding/subtracting 360
 
 5b. right ascension value needs to be in the same quadrant as L
 
 Lquadrant  = (floor( L/90)) * 90
 RAquadrant = (floor(RA/90)) * 90
 RA = RA + (Lquadrant - RAquadrant)
 
 5c. right ascension value needs to be converted into hours
 
 RA = RA / 15
 
 6. calculate the Sun's declination
 
 sinDec = 0.39782 * sin(L)
 cosDec = cos(asin(sinDec))
 
 7a. calculate the Sun's local hour angle
 
 cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude))
 
 if (cosH >  1)
 the sun never rises on this location (on the specified date)
 if (cosH < -1)
 the sun never sets on this location (on the specified date)
 
 7b. finish calculating H and convert into hours
 
 if if rising time is desired:
 H = 360 - acos(cosH)
 if setting time is desired:
 H = acos(cosH)
 
 H = H / 15
 
 8. calculate local mean time of rising/setting
 
 T = H + RA - (0.06571 * t) - 6.622
 
 9. adjust back to UTC
 
 UT = T - lngHour
 NOTE: UT potentially needs to be adjusted into the range [0,24) by adding/subtracting 24
 
 10. convert UT value to local time zone of latitude/longitude
 
 localT = UT + localOffset
 
 *******************************************************************************************/

// helpers to make it easier to transcribe the formula (which uses degrees everywhere)

inline static double deg_to_rad(double x)
{
    return (M_PI / 180.0) * x;
}

inline static double rad_to_deg(double x)
{
    return (180.0 / M_PI) * x;
}

inline static double deg_sin(double x)
{
    return sin(deg_to_rad(x));
}

inline static double deg_asin(double x)
{
    return rad_to_deg(asin(x));
}

inline static double deg_atan(double x)
{
    return rad_to_deg(atan(x));
}

inline static double deg_tan(double x)
{
    return tan(deg_to_rad(x));
}

inline static double deg_cos(double x)
{
    return cos(deg_to_rad(x));
}

inline static double deg_acos(double x)
{
    return rad_to_deg(acos(x));
}

inline static double normalize_range(double v, double max)
{
    while (v < 0) {
        v += max;
    }
    
    while (v >= max) {
        v -= max;
    }
    
    return v;
}

typedef enum {
    SunEventRise,
    SunEventSet,
} SunEvent;

@implementation CLLocation (SunriseSunset)

- (NSDate *)dateForSunEvent:(const SunEvent)event withZenith:(const double)zenith
{
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDateComponents *dateComponents = [cal components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSTimeZoneCalendarUnit) fromDate:self.timestamp];
    
    const double month = [dateComponents month];
    const double year = [dateComponents year];
    const double day = [dateComponents day];
    
    // step 1
    const double N1 = floor(275.0 * month / 9.0);
    const double N2 = floor((month + 9.0) / 12.0);
    const double N3 = (1.0 + floor((year - 4.0 * floor(year / 4.0) + 2.0) / 3.0));
    const double N = N1 - (N2 * N3) + day - 30.0;
    
    // step 2
    const double lngHour = self.coordinate.longitude / 15.0;
    double t;
    
    if (event == SunEventRise) {
        t = N + ((6.0 - lngHour) / 24.0);
    } else {
        t = N + ((18.0 - lngHour) / 24.0);
    }
    
    // step 3
    const double M = (0.9856 * t) - 3.289;
    
    // step 4
    double L = M + (1.916 * deg_sin(M)) + (0.020 * deg_sin(2 * M)) + 282.634;
    L = normalize_range(L, 360);

    // step 5
    double RA = deg_atan(0.91764 * deg_tan(L));
    RA = normalize_range(RA, 360);

    const double Lquadrant  = (floor(L/90.0)) * 90.0;
    const double RAquadrant = (floor(RA/90.0)) * 90.0;
    RA = RA + (Lquadrant - RAquadrant);
    RA = RA / 15.0;

    // step 6
    const double sinDec = 0.39782 * deg_sin(L);
    const double cosDec = deg_cos(deg_asin(sinDec));
    
    // step 7
    const double cosH = (deg_cos(zenith) - (sinDec * deg_sin(self.coordinate.latitude))) / (cosDec * deg_cos(self.coordinate.latitude));
    
    if (cosH > 1) {
        // the sun never rises on this location (on the specified date)
        return nil;
    } else if (cosH < -1) {
        // the sun never sets on this location (on the specified date)
        return nil;
    }
    
    double H;
    
    if (event == SunEventRise) {
        H = 360.0 - deg_acos(cosH);
    } else {
        H = deg_acos(cosH);
    }
    
    H = H / 15.0;
    
    // step 8
    const double T = H + RA - (0.06571 * t) - 6.622;
    
    // step 9
    const double UT = normalize_range(T - lngHour, 24);
    
    // step 10
    const double localOffset = [[dateComponents timeZone] secondsFromGMTForDate:self.timestamp] / 3600.0;
    const double localT = normalize_range(UT + localOffset, 24);

    // convert to an NSDate
    const NSInteger hour = trunc(localT);
    const NSInteger hourSeconds = 3600 * (localT - hour);
    const NSInteger minute = hourSeconds / 60;
    const NSInteger second = hourSeconds - (minute * 60);

    [dateComponents setHour:hour];
    [dateComponents setMinute:minute];
    [dateComponents setSecond:second];
    
    return [cal dateFromComponents:dateComponents];
}

- (NSDate *)sunriseDate
{
    return [self dateForSunEvent:SunEventRise withZenith:90];
}

- (NSDate *)sunsetDate
{
    return [self dateForSunEvent:SunEventSet withZenith:90];
}

- (NSDate *)dawnDate
{
    return [self dateForSunEvent:SunEventRise withZenith:83];
}

- (NSDate *)duskDate
{
    return [self dateForSunEvent:SunEventSet withZenith:83];
}

@end
