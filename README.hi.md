# Import-CaCertificates
[![संस्करण](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates)
[![PowerShell](https://img.shields.io/badge/powershell-7.5%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![प्लेटफ़ॉर्म](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)

<!-- md-i18n:switcher -->
**अन्य भाषाओं में:** [English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · हिन्दी · [Español](README.es.md) · [Русский](README.ru.md)

- [1. अवलोकन](#1-अवलोकन)
- [2. मुख्य विशेषताएँ](#2-मुख्य-विशेषताएँ)
- [3. सिस्टम आवश्यकताएँ](#3-सिस्टम-आवश्यकताएँ)
- [4. त्वरित शुरुआत गाइड](#4-त्वरित-शुरुआत-गाइड)
- [5. इंस्टॉलेशन और सेटअप](#5-इंस्टॉलेशन-और-सेटअप)
- [6. यह कैसे काम करता है](#6-यह-कैसे-काम-करता-है)
- [7. Let's Encrypt एकीकरण गाइड](#7-lets-encrypt-एकीकरण-गाइड)
- [8. उपयोग के उदाहरण](#8-उपयोग-के-उदाहरण)
- [9. पैरामीटर संदर्भ](#9-पैरामीटर-संदर्भ)
- [10. समस्या निवारण](#10-समस्या-निवारण)
- [11. लाइसेंस और आभार](#11-लाइसेंस-और-आभार)

***

## 1. अवलोकन

**Import-CaCertificates** एक पेशेवर PowerShell उपयोगिता है, जो Root और Intermediate CA प्रमाणपत्रों को डाउनलोड करके Windows Certificate Store में आयात करने की प्रक्रिया को स्वचालित करने के लिए बनाई गई है। यह फ़ायरवॉल के पीछे चलने वाले सर्वरों, स्वचालित डिप्लॉयमेंट, तथा hMailServer और Exim जैसे मेल सर्वरों में आने वाली "Unknown CA" त्रुटियों को ठीक करने के लिए विशेष रूप से उपयोगी है।

### मुख्य उद्देश्य
यह स्क्रिप्ट सुनिश्चित करती है कि आपका Windows वातावरण आवश्यक Certificate Authorities पर भरोसा करे:
- सीधे URL से प्रमाणपत्र सुरक्षित रूप से डाउनलोड करके।
- Root CA को `Trusted Root Certification Authorities` स्टोर में आयात करके।
- Intermediate CA को `Intermediate Certification Authorities` स्टोर में आयात करके।
- ट्रस्ट चेन को अद्यतन रखने का साफ़, स्वचालित तरीक़ा देकर।

***

## 2. मुख्य विशेषताएँ

- ✨ **स्वचालित आयात** - Root और Intermediate दोनों प्रमाणपत्र एक ही बार में संभालता है।
- 🔍 **सत्यापन** - आयात से पहले प्रमाणपत्र की अखंडता जाँचता है।
- 🛠️ **प्रशासनिक सुरक्षा** - उचित अनुमतियाँ सुनिश्चित करने के लिए एलिवेशन जाँच शामिल है।
- 🔄 **बलपूर्वक अद्यतन** - मौजूदा प्रमाणपत्रों को दोबारा आयात करने का विकल्प।
- 📂 **स्वतः सफ़ाई** - जब तक अन्यथा न कहा जाए, अस्थायी फ़ाइलें स्वतः हटा देता है।
- 📝 **विस्तृत लॉगिंग** - आयात प्रक्रिया पर चरण-दर-चरण कंसोल प्रतिक्रिया।

***

## 3. सिस्टम आवश्यकताएँ

- **ऑपरेटिंग सिस्टम**: Windows 7, Windows Server 2012 R2 या बाद का संस्करण।
- **PowerShell**: संस्करण 7.5 या उससे ऊपर (PowerShell Core 7.x समर्थित)।
- **अनुमतियाँ**: स्थानीय व्यवस्थापक (Local Administrator) विशेषाधिकार — सिस्टम प्रमाणपत्र स्टोर बदलने के लिए आवश्यक।
- **नेटवर्क**: स्रोत URL से प्रमाणपत्र डाउनलोड करने के लिए इंटरनेट पहुँच।

***

## 4. त्वरित शुरुआत गाइड

### चरण 1: स्क्रिप्ट डाउनलोड करें
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paulmann/Import-CaCertificates/main/Import-CaCertificates.ps1" -OutFile "Import-CaCertificates.ps1"
```

### चरण 2: व्यवस्थापक के रूप में चलाएँ
PowerShell को व्यवस्थापक के रूप में खोलें और चलाएँ:
```powershell
.\Import-CaCertificates.ps1 -RootUrl "https://example.com/root.crt" -IntermediateUrl "https://example.com/intermediate.crt"
```

***

## 5. इंस्टॉलेशन और सेटअप

1. इस रिपॉज़िटरी को क्लोन या डाउनलोड करें।
2. सुनिश्चित करें कि आपके सत्र के लिए `Set-ExecutionPolicy RemoteSigned` कॉन्फ़िगर है।
3. स्क्रिप्ट को अपने tools कैटलॉग में रखें (उदाहरण: `C:\Scripts\`)।

***

## 6. यह कैसे काम करता है

स्क्रिप्ट एक सुरक्षित निष्पादन क्रम का पालन करती है:
1. **विशेषाधिकार जाँच**: सत्यापित करता है कि स्क्रिप्ट प्रशासनिक अधिकारों के साथ चल रही है।
2. **वातावरण सेटअप**: प्रमाणपत्र प्रोसेसिंग के लिए एक अस्थायी कैटलॉग बनाता है।
3. **डाउनलोड चरण**: `Invoke-WebRequest` की सहायता से प्रमाणपत्र प्राप्त करता है।
4. **आयात चरण**: 
   - Root प्रमाणपत्र -> `LocalMachine\Root`
   - Intermediate प्रमाणपत्र -> `LocalMachine\CA`
5. **सफ़ाई**: अस्थायी फ़ाइलें और ऑब्जेक्ट हटाता है।

***

## 7. Let's Encrypt एकीकरण गाइड

Let's Encrypt प्रमाणपत्रों के लिए अक्सर आवश्यक होता है कि Windows सेवाएँ (जैसे hMailServer या Exim) विशिष्ट Root और Intermediate CA पर भरोसा करें।

### 7.1 विशिष्ट कमांड (Let's Encrypt ISRG Root X1)
मानक Let's Encrypt चेन पर भरोसा करने के लिए:
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrgrootx1.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-r3.pem"
```

### 7.2 उन्नत / अतिरिक्त कमांड (क्रॉस-साइन्ड श्रृंखलाएँ)
उन वातावरणों के लिए जिन्हें पुराने DST Root CA X3 क्रॉस-साइन की आवश्यकता है (लेगेसी संगतता के लिए):
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrg-root-x2.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-e1.pem" `
    -Force
```

***

## 8. उपयोग के उदाहरण

### केवल Root CA आयात करें
```powershell
.\Import-CaCertificates.ps1 -RootUrl "http://cacerts.digicert.com/DigiCertGlobalRootG2.crt"
```

### अस्थायी फ़ाइलें रखते हुए आयात करें (डिबगिंग के लिए)
```powershell
.\Import-CaCertificates.ps1 -RootUrl "..." -KeepFiles
```

***

## 9. पैरामीटर संदर्भ

| पैरामीटर | प्रकार | आवश्यक | विवरण |
|-----------|------|----------|-------------|
| `RootUrl` | String | **हाँ** | Root CA प्रमाणपत्र फ़ाइल का URL (.crt, .cer, .pem)। |
| `IntermediateUrl` | String | नहीं | Intermediate CA प्रमाणपत्र फ़ाइल का URL। |
| `Force` | Switch | नहीं | प्रमाणपत्र पहले से मौजूद होने पर भी उन्हें बलपूर्वक दोबारा आयात करें। |
| `KeepFiles` | Switch | नहीं | पूरा होने के बाद अस्थायी फ़ाइलें न हटाएँ। |

***

## 10. समस्या निवारण

- **त्रुटि: स्क्रिप्ट को एलिवेटेड रूप में चलाना आवश्यक है** - PowerShell पर राइट-क्लिक करें और "Run as Administrator" चुनें।
- **hMailServer में Unknown CA** - स्क्रिप्ट चलाने के बाद hMailServer सेवा को पुनः आरंभ करें, ताकि वह नए विश्वसनीय CA उठा ले।
- **डाउनलोड विफल** - सुनिश्चित करें कि आपका फ़ायरवॉल प्रमाणपत्र प्रदाता के लिए आउटबाउंड HTTPS अनुरोधों की अनुमति देता है।

***

## 11. लाइसेंस और आभार

### लाइसेंस
यह परियोजना **PolyForm Noncommercial License 1.0.0** के अंतर्गत लाइसेंस प्राप्त है।

### कॉपीराइट
Copyright © 2025 Mikhail Deynekin.
**लेखक**: Mikhail Deynekin
- **ईमेल**: m@deynekin.com
- **GitHub**: [paulmann](https://github.com/paulmann)

***

## ⭐ परियोजना का समर्थन करें
यदि इस उपकरण ने प्रमाणपत्र संबंधी समस्याएँ सुलझाने में आपकी मदद की, तो कृपया GitHub पर इसे स्टार दें!
