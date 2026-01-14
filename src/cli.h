#ifndef CLI_H
#define CLI_H

#include <QObject>
#include <QVariant>

class ImageWriter;
class QCoreApplication;

class Cli : public QObject
{
    Q_OBJECT
public:
    explicit Cli(int &argc, char *argv[]);
    virtual ~Cli();
    int run();

protected:
    QCoreApplication *_app;
    ImageWriter *_imageWriter;
    int _lastPercent;
    QByteArray _lastMsg;
    bool _quiet;
    bool _isSpuMode;

    void _printProgress(const QByteArray &msg, QVariant now, QVariant total);
    void _clearLine();

protected slots:
    void onSuccess();
    void onError(QVariant msg);
    void onDownloadProgress(QVariant dlnow, QVariant dltotal);
    void onVerifyProgress(QVariant now, QVariant total);
    void onPreparationStatusUpdate(QVariant msg);
    // SPU copy slots
    void onSpuCopySuccess();
    void onSpuCopyError(QVariant msg);
    void onSpuCopyProgress(QVariant now, QVariant total);
    void onSpuPreparationStatusUpdate(QVariant msg);

signals:

};

#endif // CLI_H
