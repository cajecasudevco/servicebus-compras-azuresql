using System.Text;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.EntityFrameworkCore;
using ProcesaCompra.Data;
using ProcesaCompra.Models;

namespace ProcesaCompra;

public class Worker : BackgroundService
{
    private readonly string _conn;
    private readonly string _queueEntrada;
    private readonly string _queueHombre;
    private readonly string _queueMujer;

    private readonly ServiceBusClient _sbClient;
    private readonly ServiceBusProcessor _processor;
    private readonly ServiceBusSender _senderHombre;
    private readonly ServiceBusSender _senderMujer;
    private readonly IServiceProvider _sp;

    public Worker(IConfiguration cfg, IServiceProvider sp)
    {
        _sp = sp;

        _conn = cfg["ServiceBus:ConnectionString"]
            ?? Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION_STRING")
            ?? throw new InvalidOperationException("Falta SERVICEBUS_CONNECTION_STRING");

        _queueEntrada = cfg["ServiceBus:QueueName"]
            ?? Environment.GetEnvironmentVariable("SERVICE_BUS_QUEUE_NAME")
            ?? "compras";

        // Destinos (Basic tier = colas)
        _queueHombre = cfg["ServiceBus:QueueHombre"]
            ?? Environment.GetEnvironmentVariable("HOMBRE_QUEUE_NAME")
            ?? "hombreq";

        _queueMujer = cfg["ServiceBus:QueueMujer"]
            ?? Environment.GetEnvironmentVariable("MUJER_QUEUE_NAME")
            ?? "mujerq";

        _sbClient = new ServiceBusClient(_conn);

        _processor = _sbClient.CreateProcessor(_queueEntrada, new ServiceBusProcessorOptions
        {
            AutoCompleteMessages = false,
            MaxConcurrentCalls = 16,
            PrefetchCount = 100
        });

        _senderHombre = _sbClient.CreateSender(_queueHombre);
        _senderMujer = _sbClient.CreateSender(_queueMujer);

        _processor.ProcessMessageAsync += OnMessageAsync;
        _processor.ProcessErrorAsync += OnErrorAsync;
    }

    private async Task OnMessageAsync(ProcessMessageEventArgs args)
    {
        try
        {
            var body = Encoding.UTF8.GetString(args.Message.Body);
            var doc = JsonDocument.Parse(body).RootElement;

            var nombre = doc.GetProperty("Nombre").GetString() ?? string.Empty;
            var genero = (doc.TryGetProperty("Genero", out var g) ? g.GetString() : null)?.ToLowerInvariant() ?? string.Empty;

            decimal monto = 0m;
            if (doc.TryGetProperty("Monto", out var m) && m.ValueKind != JsonValueKind.Null)
            {
                if (m.ValueKind == JsonValueKind.Number && m.TryGetDecimal(out var parsedNum))
                    monto = parsedNum;
                else if (m.ValueKind == JsonValueKind.String && decimal.TryParse(m.GetString(), out var parsedStr))
                    monto = parsedStr;
            }

            var fecha = DateTimeOffset.UtcNow;
            if (doc.TryGetProperty("Fecha", out var f) && f.ValueKind == JsonValueKind.String)
                DateTimeOffset.TryParse(f.GetString(), out fecha);

            if (genero != "hombre" && genero != "mujer")
                throw new InvalidOperationException("Genero inválido");

            // Persistir (usar DbContextPool en Program.cs para menos GC)
            using var scope = _sp.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ComprasDbContext>();
            db.Compras.Add(new Compra { Nombre = nombre, Genero = genero, Monto = monto, Fecha = fecha });
            await db.SaveChangesAsync();

            // Envío a cola destino (reutilizando sender; menos overhead)
            var forwardMsg = new ServiceBusMessage(args.Message.Body)
            {
                ContentType = "application/json",
                CorrelationId = args.Message.CorrelationId ?? Guid.NewGuid().ToString()
            };
            forwardMsg.ApplicationProperties["genero"] = genero;

            var sender = genero == "hombre" ? _senderHombre : _senderMujer;
            await sender.SendMessageAsync(forwardMsg);

            await args.CompleteMessageAsync(args.Message);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[ERR] {ex.Message}");
            // Para demo: abandonamos; en prod, decide DeadLetter según el tipo de error.
            await args.AbandonMessageAsync(args.Message);
        }
    }

    private Task OnErrorAsync(ProcessErrorEventArgs args)
    {
        Console.WriteLine($"[SB-ERROR] {args.Exception.Message}");
        return Task.CompletedTask;
    }

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        await base.StartAsync(cancellationToken);
        await _processor.StartProcessingAsync(cancellationToken);
        Console.WriteLine($"[START] {_queueEntrada} -> hombre='{_queueHombre}', mujer='{_queueMujer}' (concurrency=16, prefetch=100)");
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        await _processor.StopProcessingAsync(cancellationToken);
        await base.StopAsync(cancellationToken);
    }

    public override void Dispose()
    {
        base.Dispose();
        _senderHombre?.DisposeAsync().AsTask().GetAwaiter().GetResult();
        _senderMujer?.DisposeAsync().AsTask().GetAwaiter().GetResult();
        _processor?.DisposeAsync().AsTask().GetAwaiter().GetResult();
        _sbClient?.DisposeAsync().AsTask().GetAwaiter().GetResult();
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken) => Task.CompletedTask;
}