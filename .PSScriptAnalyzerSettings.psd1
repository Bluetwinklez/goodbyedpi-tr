@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Etkileşimli CLI renkli çıktısı Yaz() içinde bilinçli olarak Write-Host kullanır.
        'PSAvoidUsingWriteHost'
        # Dns ve Https gibi 's' ile biten teknik kısaltmalarda yanlış pozitif üretir.
        'PSUseSingularNouns'
        # İç yardımcı işlevler dışa aktarılan cmdlet modülü değildir.
        'PSUseShouldProcessForStateChangingFunctions'
        # Üst düzey param() değişkenleri Main() içinde okunduğunda yanlış pozitif üretir.
        'PSReviewUnusedParameter'
        # Depo mevcut UTF-8 kodlama biçimini korur.
        'PSUseBOMForUnicodeEncodedFile'
    )
}

